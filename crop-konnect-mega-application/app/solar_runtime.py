from __future__ import annotations

import asyncio
import logging
import threading
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any

import minimalmodbus
import serial

from app.config import Settings, get_settings
from app.gpio_relay import GpioOutput, create_gpio_output
from app.settings_cache import get_settings_cache


logger = logging.getLogger(__name__)

SLAVE_ID = 1
SERIAL_TIMEOUT = 1.0
BAUD_SOLAR = 4800
SOLAR_UNAVAILABLE_BACKOFF_SECONDS = 30.0
MIN_RELAY_STABILIZE_SECONDS = 30.0


class SolarRelayController:
    def __init__(self, settings: Settings) -> None:
        self.enabled = bool(settings.relay_control_enabled)
        self.active_low = bool(settings.relay_active_low)
        self.settle_seconds = max(0.0, float(settings.relay_settle_seconds))
        self.stabilize_seconds = max(
            MIN_RELAY_STABILIZE_SECONDS,
            self.settle_seconds,
        )
        self.pin = settings.relay_solar_pin
        self._gpio: GpioOutput | None = None
        self._active = False

        if not self.enabled or self.pin is None:
            return

        try:
            self._gpio = create_gpio_output(settings, [self.pin], logger)
            self._gpio.output(self.pin, self._off_value())
            logger.info(
                "Solar relay enabled with %s driver on GPIO pin %s",
                self._gpio.driver_name,
                self.pin,
            )
        except Exception as exc:
            logger.warning("Solar relay setup failed; relay control disabled: %s", exc)
            self.enabled = False
            self._gpio = None

    def _on_value(self) -> int:
        return 0 if self.active_low else 1

    def _off_value(self) -> int:
        return 1 if self.active_low else 0

    def on(self) -> bool:
        if not self.enabled or self._gpio is None or self.pin is None:
            return False
        if self._active:
            return False
        self._gpio.output(self.pin, self._on_value())
        self._active = True
        logger.info("Solar relay ON on GPIO pin %s", self.pin)
        return True

    def off(self) -> None:
        if not self.enabled or self._gpio is None or self.pin is None:
            return
        if not self._active:
            return
        self._gpio.output(self.pin, self._off_value())
        self._active = False
        logger.info("Solar relay OFF on GPIO pin %s", self.pin)

    def cleanup(self) -> None:
        self.off()
        if self._gpio is not None:
            try:
                self._gpio.cleanup()
            except Exception:
                pass

    def status(self) -> dict[str, Any]:
        return {
            "enabled": self.enabled,
            "active_low": self.active_low,
            "settle_seconds": self.settle_seconds,
            "stabilize_seconds": self.stabilize_seconds,
            "pin": self.pin,
            "active": self._active,
        }


@dataclass
class SolarReadingCache:
    value: float | None = None
    updated_at: datetime | None = None
    last_error: str | None = None
    _lock: threading.Lock = field(default_factory=threading.Lock, init=False, repr=False)

    def update(self, value: float | None) -> None:
        with self._lock:
            self.value = value
            self.updated_at = datetime.now(timezone.utc)
            self.last_error = None

    def mark_error(self, error: str) -> None:
        with self._lock:
            self.last_error = error
            self.updated_at = datetime.now(timezone.utc)

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            return {
                "value": self.value,
                "updated_at": self.updated_at,
                "last_error": self.last_error,
            }


def _create_instrument(port: str | None) -> minimalmodbus.Instrument | None:
    if not port:
        return None

    try:
        instrument = minimalmodbus.Instrument(port, SLAVE_ID)
        instrument.serial.baudrate = BAUD_SOLAR
        instrument.serial.bytesize = 8
        instrument.serial.parity = serial.PARITY_NONE
        instrument.serial.stopbits = 1
        instrument.serial.timeout = SERIAL_TIMEOUT
        instrument.mode = minimalmodbus.MODE_RTU
        # Flush before every transaction and release the port after it.
        #
        # These were both False, which is why solar failed intermittently:
        # relay switching leaves garbage bytes on the line, an unflushed buffer
        # desyncs the RTU frame (reported as CRC/invalid-response), and holding
        # the port open leaves a dead file descriptor behind whenever the USB
        # adapter re-enumerates.
        instrument.clear_buffers_before_each_transaction = True
        instrument.close_port_after_each_call = True
        return instrument
    except Exception as exc:
        logger.warning("Failed to configure solar port %s: %s", port, exc)
        return None


def _read_register(
    instrument: minimalmodbus.Instrument | None,
    register_address: int,
    decimals: int = 0,
    function_code: int = 3,
) -> float | None:
    if instrument is None:
        return None
    try:
        return instrument.read_register(register_address, decimals, functioncode=function_code)
    except Exception:
        return None


def read_solar_radiation(instrument: minimalmodbus.Instrument | None) -> float | None:
    value = _read_register(instrument, register_address=0, decimals=0, function_code=3)
    if value is None:
        value = _read_register(instrument, register_address=0, decimals=0, function_code=4)
    return float(value) if value is not None else None


class SolarSensorPoller:
    def __init__(
        self,
        settings: Settings | None = None,
        cache: SolarReadingCache | None = None,
        port_resolver: Any | None = None,
    ) -> None:
        self.settings = settings or get_settings()
        self.cache = cache or SolarReadingCache()
        # Shared with the sensor poller so solar is bound to a *verified*
        # adapter. Solar is one of the four protocol-identical 4800-baud
        # sensors, so an unverified port could just as easily be the rain gauge.
        self.port_resolver = port_resolver
        self.running = False
        self.task: asyncio.Task | None = None
        self.instrument: minimalmodbus.Instrument | None = None
        self.relay = SolarRelayController(self.settings)
        self._settings_cache = get_settings_cache(self.settings)
        self.last_settings_at: datetime | None = None
        self._last_solar_enabled: bool | None = None
        self._last_solar_interval_seconds: int | None = None
        self._unavailable_until: datetime | None = None

    def status(self) -> dict[str, Any]:
        return {
            "enabled": self.settings.serial_reader_enabled,
            "running": self.running,
            "port": self.settings.solar_port,
            "baudrate": BAUD_SOLAR,
            "cache": self.cache.snapshot(),
            "solar_enabled": self._last_solar_enabled,
            "solar_interval_seconds": self._last_solar_interval_seconds,
            "last_settings_at": self.last_settings_at,
            "relay": self.relay.status(),
        }

    def _load_solar_runtime(self) -> tuple[bool, int]:
        """Solar enable flag + cadence, from the shared settings cache.

        This used to open its own Session and run the full station-settings load
        once per second, in parallel with the sensor poller doing the same. Both
        now share one cached read.
        """
        default_interval = max(1, int(self.settings.serial_poll_interval_seconds))
        try:
            runtime = self._settings_cache.get()
            if runtime is None:
                # Nothing cached yet and the database is unreachable. Keep the
                # previous decision rather than flapping solar off.
                enabled = bool(self._last_solar_enabled)
                interval_seconds = self._last_solar_interval_seconds or default_interval
            else:
                enabled = bool(runtime.enabled.get("solar", False))
                interval_seconds = default_interval
                item = runtime.sensor_read_plan.get("solar")
                if item:
                    try:
                        reads_per_day = max(0, int(item.get("reads_per_day", 0)))
                    except Exception:
                        reads_per_day = 0
                    if reads_per_day > 0:
                        interval_seconds = max(1, round(86400 / reads_per_day))
            self.last_settings_at = datetime.now(timezone.utc)
        except Exception as exc:
            logger.warning("Failed to load solar setting; keeping previous state: %s", exc)
            enabled = bool(self._last_solar_enabled)
            interval_seconds = self._last_solar_interval_seconds or default_interval
            self.last_settings_at = datetime.now(timezone.utc)

        if enabled != self._last_solar_enabled or interval_seconds != self._last_solar_interval_seconds:
            self._last_solar_enabled = enabled
            self._last_solar_interval_seconds = interval_seconds
            logger.info(
                "Solar runtime setting loaded from database for %s: enabled=%s interval_seconds=%s",
                self.settings.device_id,
                enabled,
                interval_seconds,
            )
        return enabled, interval_seconds

    def _load_solar_enabled(self) -> bool:
        enabled, _ = self._load_solar_runtime()
        return enabled

    def _is_in_backoff(self) -> bool:
        if self._unavailable_until is None:
            return False
        if datetime.now(timezone.utc) < self._unavailable_until:
            return True
        self._unavailable_until = None
        return False

    def _mark_unavailable(self, reason: str) -> None:
        now = datetime.now(timezone.utc)
        previous_retry_at = self._unavailable_until
        self._unavailable_until = now + timedelta(seconds=SOLAR_UNAVAILABLE_BACKOFF_SECONDS)
        if previous_retry_at is None or previous_retry_at <= now:
            logger.warning(
                "solar unavailable: %s; retrying after %.0f second(s)",
                reason,
                SOLAR_UNAVAILABLE_BACKOFF_SECONDS,
            )

    async def _sleep_with_settings_checks(
        self,
        duration_seconds: float,
        current_enabled: bool,
        current_interval_seconds: int,
    ) -> None:
        remaining = max(0.0, duration_seconds)
        refresh_interval = max(0.25, float(self.settings.settings_refresh_interval_seconds))
        while self.running and remaining > 0:
            chunk = min(refresh_interval, remaining)
            await asyncio.sleep(chunk)
            remaining -= chunk
            latest_enabled, latest_interval_seconds = self._load_solar_runtime()
            if (
                latest_enabled != current_enabled
                or latest_interval_seconds != current_interval_seconds
            ):
                return

    def _solar_port(self) -> str | None:
        """The device to read, or None when solar's identity is unconfirmed."""
        if self.port_resolver is not None:
            try:
                return self.port_resolver.device_for("solar")
            except Exception as exc:
                logger.warning("Solar port resolution failed: %s", exc)
                return None
        return self.settings.solar_port

    def _ensure_instrument(self) -> minimalmodbus.Instrument | None:
        if self._is_in_backoff():
            return None
        if self.instrument is not None:
            return self.instrument
        port = self._solar_port()
        if port is None:
            self._mark_unavailable("solar adapter identity not confirmed")
            return None
        self.instrument = _create_instrument(port)
        if self.instrument is None:
            self._mark_unavailable("serial instrument could not be opened")
        return self.instrument

    def _read_once(self) -> float | None:
        instrument = self._ensure_instrument()
        if instrument is None:
            return None

        value = read_solar_radiation(instrument)
        if value is not None:
            return value

        try:
            if instrument.serial and instrument.serial.is_open:
                instrument.serial.close()
        except Exception:
            pass

        port = self._solar_port()
        if port is None:
            self._mark_unavailable("solar adapter identity not confirmed")
            return None
        self.instrument = _create_instrument(port)
        if self.instrument is None:
            self._mark_unavailable("serial instrument could not be reopened")
            return None
        value = read_solar_radiation(self.instrument)
        if value is None:
            self._mark_unavailable("read returned no data after reconnect")
        else:
            self._unavailable_until = None
        return value

    async def start(self) -> None:
        if not self.settings.serial_reader_enabled or self.running:
            return
        self.running = True
        self.task = asyncio.create_task(self._run_loop())
        logger.info("Solar sensor poller started for device %s", self.settings.device_id)

    async def stop(self) -> None:
        self.running = False
        if self.task:
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass
            self.task = None
        if self.instrument:
            try:
                if self.instrument.serial and self.instrument.serial.is_open:
                    self.instrument.serial.close()
            except Exception:
                pass
            self.instrument = None
        self.relay.cleanup()

    async def _run_loop(self) -> None:
        while self.running:
            enabled, interval_seconds = self._load_solar_runtime()
            if enabled:
                try:
                    if self.relay.on() and self.relay.stabilize_seconds > 0:
                        logger.info(
                            "Solar relay stabilizing: pin=%s seconds=%.2f",
                            self.relay.pin,
                            self.relay.stabilize_seconds,
                        )
                        await asyncio.sleep(self.relay.stabilize_seconds)
                    await self._read_and_store()
                finally:
                    self.relay.off()
                sleep_seconds = max(1.0, float(interval_seconds))
            else:
                self.relay.off()
                self.cache.mark_error("solar disabled by station settings")
                sleep_seconds = max(0.25, float(self.settings.settings_refresh_interval_seconds))
            await self._sleep_with_settings_checks(sleep_seconds, enabled, interval_seconds)

    async def _read_and_store(self) -> None:
        try:
            if self._is_in_backoff():
                logger.info("solar skipped this cycle because it is in retry backoff")
                return
            logger.info("solar read started")
            # Blocking Modbus I/O must not run on the event loop, and it needs a
            # hard deadline so a wedged adapter cannot stall the API.
            timeout = max(1.0, float(self.settings.sensor_read_timeout_seconds))
            try:
                value = await asyncio.wait_for(
                    asyncio.to_thread(self._read_once), timeout=timeout
                )
            except asyncio.TimeoutError:
                self._mark_unavailable(f"read exceeded {timeout:.1f}s deadline")
                self.cache.mark_error("solar read timed out")
                logger.warning("solar read timed out after %.1fs", timeout)
                return
            if value is None:
                self.cache.mark_error("solar read returned no data")
                logger.warning("solar read returned no data")
                return
            self.cache.update(value)
            logger.info("solar reading updated: %s", value)
        except Exception as exc:
            self.cache.mark_error(str(exc))
            logger.exception("solar read failed: %s", exc)
