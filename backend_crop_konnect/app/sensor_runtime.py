import asyncio
import logging
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

import minimalmodbus
import serial
from rich.align import Align
from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from app.config import Settings, get_settings
from app.db import SessionLocal
from app.gpio_relay import GpioOutput, create_gpio_output
from app.schemas import IngestRequest, ReadingPayload
from app.serial_ports import PortResolver, SignatureStore
from app.settings_cache import get_settings_cache
from app.station_settings import StationRuntimeSettings
from app.services import create_reading_sync, run_broadcast
from app.solar_runtime import SolarReadingCache


logger = logging.getLogger(__name__)
console = Console()

SLAVE_ID = 1
SERIAL_TIMEOUT = 1.0
SENSOR_UNAVAILABLE_BACKOFF_SECONDS = 30.0
MIN_RELAY_STABILIZE_SECONDS = 30.0
BAUD_WIND = 4800
BAUD_SOIL = 9600
BAUD_RAIN = 4800
BAUD_SOLAR = 4800
UNIVERSAL_DIRS = [
    "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
    "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
]
WEEKDAY_KEYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")


@dataclass(frozen=True)
class SensorPortConfig:
    port: str | None
    baudrate: int


class RelayController:
    def __init__(self, settings: Settings) -> None:
        self.enabled = bool(settings.relay_control_enabled)
        self.active_low = bool(settings.relay_active_low)
        self.settle_seconds = max(0.0, float(settings.relay_settle_seconds))
        self.stabilize_seconds = max(
            max(0.0, float(getattr(settings, "relay_min_stabilize_seconds", MIN_RELAY_STABILIZE_SECONDS))),
            self.settle_seconds,
        )
        self.pins = {
            "wind": settings.relay_wind_pin,
            "soil": settings.relay_soil_pin,
            "rain": settings.relay_rain_pin,
            "solar": settings.relay_solar_pin,
        }
        self._gpio: GpioOutput | None = None
        self._active: set[str] = set()

        if not self.enabled:
            return

        try:
            pins = [pin for pin in self.pins.values() if pin is not None]
            self._gpio = create_gpio_output(settings, pins, logger)
            for pin in self.pins.values():
                if pin is None:
                    continue
                self._gpio.output(pin, self._off_value())
            logger.info(
                "Relay control enabled with %s driver and pins: %s",
                self._gpio.driver_name,
                self.pins,
            )
        except Exception as exc:
            logger.warning("Relay GPIO setup failed; relay control disabled: %s", exc)
            self.enabled = False
            self._gpio = None

    def _on_value(self) -> int:
        return 0 if self.active_low else 1

    def _off_value(self) -> int:
        return 1 if self.active_low else 0

    def on(self, group: str | None) -> bool:
        if not self.enabled or self._gpio is None or group is None:
            return False
        pin = self.pins.get(group)
        if pin is None:
            return False
        if group in self._active:
            return False
        self._gpio.output(pin, self._on_value())
        self._active.add(group)
        logger.info("Relay %s ON on GPIO pin %s", group, pin)
        return True

    def off(self, group: str | None) -> None:
        if not self.enabled or self._gpio is None or group is None:
            return
        pin = self.pins.get(group)
        if pin is None:
            return
        if group not in self._active:
            return
        self._gpio.output(pin, self._off_value())
        self._active.discard(group)
        logger.info("Relay %s OFF on GPIO pin %s", group, pin)

    def sync(self, desired: dict[str, bool]) -> None:
        for group in self.pins.keys():
            if desired.get(group, False):
                self.on(group)
            else:
                self.off(group)

    def off_disabled(self, desired: dict[str, bool]) -> None:
        for group in self.pins.keys():
            if not desired.get(group, False):
                self.off(group)

    def off_all(self) -> None:
        for group in list(self.pins.keys()):
            self.off(group)

    def cleanup(self) -> None:
        self.off_all()
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
            "pins": self.pins,
            "active": sorted(self._active),
        }


def relay_group_for_sensor(sensor_name: str) -> str | None:
    if sensor_name in {"wind_speed", "wind_direction"}:
        return "wind"
    if sensor_name in {"soil", "rain", "solar"}:
        return sensor_name
    return None


def relay_groups_for_runtime(runtime: StationRuntimeSettings) -> dict[str, bool]:
    return {
        "wind": bool(
            runtime.enabled.get("wind_speed", False)
            or runtime.enabled.get("wind_direction", False)
        ),
        "soil": bool(runtime.enabled.get("soil", False)),
        "rain": bool(runtime.enabled.get("rain", False)),
        "solar": bool(runtime.enabled.get("solar", False)),
    }


def format_metric(value: float | str | None, unit: str = "") -> str:
    if value is None:
        return "N/A"
    if isinstance(value, float):
        value = round(value, 2)
    if unit:
        return f"{value} {unit}"
    return str(value)


def metric_style(value: float | None, warning_threshold: float | None = None, danger_threshold: float | None = None) -> str:
    if value is None:
        return "bold white on grey23"
    if danger_threshold is not None and value >= danger_threshold:
        return "bold white on red"
    if warning_threshold is not None and value >= warning_threshold:
        return "bold black on yellow"
    return "bold white on green4"


def build_metric_panel(title: str, value: str, style: str, subtitle: str = "") -> Panel:
    body = Text(value, justify="center", style=style)
    return Panel(
        Align.center(body, vertical="middle"),
        title=f"[bold]{title}[/bold]",
        subtitle=subtitle,
        border_style=style,
        padding=(1, 2),
    )


def build_terminal_dashboard(
    device_id: str,
    station_name: str,
    reading_payload: ReadingPayload,
    recorded_at: datetime,
    poll_interval_seconds: int,
) -> Group:
    wind_direction = "N/A"
    if reading_payload.wd_deg is not None and reading_payload.wd_dir:
        wind_direction = f"{reading_payload.wd_deg} deg ({reading_payload.wd_dir})"

    header = Panel(
        Group(
            Align.center(Text("CropConnect Live Sensor Monitor", style="bold cyan", justify="center")),
            Align.center(
                Text(
                    f"{station_name} | {device_id} | {recorded_at.astimezone(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}",
                    style="white",
                    justify="center",
                )
            ),
        ),
        border_style="cyan",
        padding=(1, 2),
    )

    grid = Table.grid(expand=True)
    for _ in range(3):
        grid.add_column(ratio=1)

    grid.add_row(
        build_metric_panel("Wind Speed", format_metric(reading_payload.ws, "m/s"), metric_style(reading_payload.ws, 8, 15), "Air Flow"),
        build_metric_panel("Wind Direction", wind_direction, "bold white on blue", "Compass"),
        build_metric_panel("Rainfall", format_metric(reading_payload.rain, "mm"), metric_style(reading_payload.rain, 2, 10), "Precipitation"),
    )
    grid.add_row(
        build_metric_panel("Soil Moisture", format_metric(reading_payload.moist, "%"), metric_style(reading_payload.moist, 60, 85), "Root Zone"),
        build_metric_panel("Soil Temp", format_metric(reading_payload.temp, "C"), metric_style(reading_payload.temp, 35, 45), "Ground Heat"),
        build_metric_panel("Solar", format_metric(reading_payload.solar, "W/m2"), metric_style(reading_payload.solar, 700, 1000), "Radiation"),
    )
    grid.add_row(
        build_metric_panel("Soil EC", format_metric(reading_payload.ec, "uS/cm"), metric_style(reading_payload.ec, 1500, 3000), "Salinity"),
        build_metric_panel("Nitrogen", format_metric(reading_payload.n, "mg/kg"), metric_style(reading_payload.n, 50, 100), "Soil N"),
        build_metric_panel("Phosphorus", format_metric(reading_payload.p, "mg/kg"), metric_style(reading_payload.p, 40, 80), "Soil P"),
    )
    grid.add_row(
        build_metric_panel("Potassium", format_metric(reading_payload.k, "mg/kg"), metric_style(reading_payload.k, 80, 150), "Soil K"),
        build_metric_panel("Soil pH", format_metric(reading_payload.ph), metric_style(reading_payload.ph, 8, 9), "Acidity"),
        build_metric_panel("Poll Interval", f"{poll_interval_seconds}s", "bold white on dark_cyan", "Backend Loop"),
    )

    footer = Panel(
        Text(
            "Live serial polling is active. Data is being stored in the database and streamed to the app APIs.",
            style="white",
            justify="center",
        ),
        border_style="grey50",
        padding=(0, 2),
    )

    return Group(header, grid, footer)

def create_instrument(
    port: str | None,
    baudrate: int,
    sensor_name: str | None = None,
) -> minimalmodbus.Instrument | None:
    if not port:
        return None

    try:
        instrument = minimalmodbus.Instrument(port, SLAVE_ID)
        instrument.serial.baudrate = baudrate
        instrument.serial.bytesize = 8
        instrument.serial.parity = serial.PARITY_NONE
        instrument.serial.stopbits = 1
        instrument.serial.timeout = SERIAL_TIMEOUT
        instrument.mode = minimalmodbus.MODE_RTU
        # Always flush before a transaction and always release the port after.
        #
        # Solar used to be special-cased to keep the port open and skip the
        # flush. Both settings were harmful: relay switching leaves garbage
        # bytes on the line, and an unflushed buffer desyncs the RTU frame so a
        # healthy sensor reports CRC/invalid-response errors. Holding the port
        # open also means a re-enumerated adapter leaves a permanently dead file
        # descriptor behind. This is the fix for the intermittent solar/rain
        # failures.
        instrument.clear_buffers_before_each_transaction = True
        instrument.close_port_after_each_call = True
        return instrument
    except Exception as exc:
        logger.warning("Failed to configure port %s: %s", port, exc)
        return None


def safe_read_register(
    instrument: minimalmodbus.Instrument | None,
    register_address: int,
    decimals: int = 0,
    function_code: int = 3,
    sensor_name: str = "unknown",
) -> float | None:
    if instrument is None:
        return None

    try:
        return instrument.read_register(register_address, decimals, functioncode=function_code)
    except minimalmodbus.NoResponseError:
        logger.warning("%s did not respond on serial port", sensor_name)
    except minimalmodbus.IllegalRequestError:
        logger.warning("%s rejected register=%s function=%s", sensor_name, register_address, function_code)
    except Exception as exc:
        logger.warning("%s read failed: %s", sensor_name, exc)
    return None


def safe_read_registers(
    instrument: minimalmodbus.Instrument | None,
    register_address: int,
    count: int,
    function_code: int = 3,
    sensor_name: str = "unknown",
) -> list[int] | None:
    if instrument is None:
        return None

    try:
        return instrument.read_registers(register_address, count, functioncode=function_code)
    except minimalmodbus.NoResponseError:
        logger.warning("%s did not respond on serial port", sensor_name)
    except minimalmodbus.IllegalRequestError:
        logger.warning("%s rejected %s-register request", sensor_name, count)
    except Exception as exc:
        logger.warning("%s block read failed: %s", sensor_name, exc)
    return None


def safe_read_register_fallback_fc(
    instrument: minimalmodbus.Instrument | None,
    register_address: int,
    decimals: int = 0,
    primary_fc: int = 3,
    fallback_fc: int = 4,
    sensor_name: str = "unknown",
) -> float | None:
    value = safe_read_register(instrument, register_address, decimals, primary_fc, sensor_name)
    if value is not None:
        return value
    return safe_read_register(instrument, register_address, decimals, fallback_fc, sensor_name)


def read_wind_speed(instrument: minimalmodbus.Instrument | None) -> float | None:
    return safe_read_register(instrument, register_address=0, decimals=1, function_code=3, sensor_name="wind_speed")


def read_wind_direction(instrument: minimalmodbus.Instrument | None) -> tuple[float, str] | None:
    """Wind direction, or None when the read failed.

    Returning ``None`` -- not ``(None, None)`` -- is load bearing. The retry and
    reconnect logic in :meth:`SerialSensorPoller._read_with_reconnect` detects a
    failed read with ``value is None``, and a two-element tuple is never None.
    While this returned ``(None, None)`` every failed direction read was scored
    as a *success*: the port was never reopened, the failure counter never
    moved, and the station published a null direction on every cycle after the
    first one that happened to work.
    """
    gear = safe_read_register(instrument, register_address=0, decimals=0, function_code=3, sensor_name="wind_dir")
    if gear is None:
        return None

    try:
        gear_index = max(0, min(15, int(gear)))
        return gear_index * 22.5, UNIVERSAL_DIRS[gear_index]
    except Exception as exc:
        logger.warning("wind_dir conversion failed: %s", exc)
        return None


def read_soil(instrument: minimalmodbus.Instrument | None) -> dict[str, float | None] | None:
    """Soil block, or None when the read failed.

    Same contract as :func:`read_wind_direction`: an all-null dict is not None,
    so returning one hid every soil failure from the retry path.
    """
    registers = safe_read_registers(instrument, register_address=0, count=7, function_code=3, sensor_name="soil")
    if not registers or len(registers) != 7:
        return None

    try:
        return {
            "moist": round(registers[0] * 0.1, 1),
            "temp": round(registers[1] * 0.1, 1),
            "ec": round(registers[2] * 0.1, 1),
            "n": round(registers[3] * 0.1, 1),
            "p": round(registers[4] * 0.1, 1),
            "k": round(registers[5] * 0.1, 1),
            "ph": round(registers[6] * 0.01, 2),
        }
    except Exception as exc:
        logger.warning("soil payload conversion failed: %s", exc)
        return None


def read_rain(instrument: minimalmodbus.Instrument | None) -> float | None:
    value = safe_read_register(instrument, register_address=0, decimals=0, function_code=3, sensor_name="rain")
    if value is None:
        return None
    return round(float(value) / 10.0, 1)


def read_solar_radiation(instrument: minimalmodbus.Instrument | None) -> float | None:
    value = safe_read_register_fallback_fc(
        instrument,
        register_address=0,
        decimals=0,
        primary_fc=3,
        fallback_fc=4,
        sensor_name="solar",
    )
    return float(value) if value is not None else None


def empty_soil_reading() -> dict[str, float | None]:
    return {"moist": None, "temp": None, "ec": None, "n": None, "p": None, "k": None, "ph": None}


class SerialSensorPoller:
    def __init__(self, settings: Settings | None = None, solar_cache: SolarReadingCache | None = None) -> None:
        self.settings = settings or get_settings()
        self.solar_cache = solar_cache
        self.task: asyncio.Task | None = None
        self.live: Live | None = None
        self.running = False
        self.last_error: str | None = None
        self.last_poll_at: datetime | None = None
        self.last_success_at: datetime | None = None
        self.last_settings_at: datetime | None = None
        self._runtime_settings: StationRuntimeSettings | None = None
        self._runtime_log_signature: tuple[Any, ...] | None = None
        self._sensor_next_due_at: dict[str, datetime] = {}
        self._sensor_last_read_at: dict[str, datetime] = {}
        # Effective cadence each sensor was last scheduled against. A change here
        # re-anchors the pending due time; see _reconcile_sensor_schedule.
        self._sensor_interval_seen: dict[str, int] = {}
        self._unreachable_cadence_logged: set[str] = set()
        self._sensor_unavailable_until: dict[str, datetime] = {}
        self._sensor_failures: dict[str, int] = {}
        self.relays = RelayController(self.settings)

        # Baud per sensor is fixed by the hardware; the *port* is resolved at
        # runtime because Linux does not name these adapters consistently.
        self.sensor_baudrates = {
            "wind_speed": BAUD_WIND,
            "wind_direction": BAUD_WIND,
            "soil": BAUD_SOIL,
            "rain": BAUD_RAIN,
            "solar": BAUD_SOLAR,
        }
        self.settings_cache = get_settings_cache(self.settings)
        self.port_resolver = PortResolver(
            {
                "wind_speed": self.settings.wind_speed_port,
                "wind_direction": self.settings.wind_direction_port,
                "soil": self.settings.soil_port,
                "rain": self.settings.rain_port,
                "solar": self.settings.solar_port,
            },
            SignatureStore.load(self.settings.sensor_signature_file),
            strict=self.settings.sensor_strict_identity,
            probe_enabled=self.settings.sensor_fingerprint_enabled,
            # The GPS receiver enumerates as ttyACM just like some RS-485
            # adapters; never probe or assign it.
            exclude_devices=[self.settings.gps_port] if self.settings.gps_port else [],
        )
        self._identity_resolved_at: datetime | None = None
        # One lock per port so a timed-out read that is still running in a
        # worker thread can never be joined by a second read on the same port.
        self._sensor_locks = {name: threading.Lock() for name in self.sensor_baudrates}
        self.instruments: dict[str, minimalmodbus.Instrument | None] = {
            name: None for name in self.sensor_baudrates
        }
        self.readers = {
            "wind_speed": lambda: self._read_with_reconnect("wind_speed", read_wind_speed),
            "wind_direction": lambda: self._read_with_reconnect("wind_direction", read_wind_direction),
            "soil": lambda: self._read_with_reconnect("soil", read_soil),
            "rain": lambda: self._read_with_reconnect("rain", read_rain),
            "solar": lambda: self._read_with_reconnect("solar", read_solar_radiation),
        }

    def status(self) -> dict[str, Any]:
        effective = self._runtime_settings
        return {
            "enabled": self.settings.serial_reader_enabled,
            "running": self.running,
            "device_id": self.settings.device_id,
            "station_name": self.settings.station_name,
            "poll_interval_seconds": self.settings.serial_poll_interval_seconds,
            "startup_delay_seconds": self.settings.serial_startup_delay_seconds,
            "inter_read_delay_ms": self.settings.sensor_inter_read_delay_ms,
            "read_order": self.settings.sensor_read_sequence,
            "solar_read_retries": self.settings.solar_read_retries,
            "console_output_enabled": self.settings.serial_console_output_enabled,
            "effective": None
            if effective is None
            else {
                "poll_interval_seconds": effective.poll_interval_seconds,
                "inter_read_delay_ms": effective.inter_read_delay_ms,
                "read_order": effective.sensor_read_sequence,
                "enabled": effective.enabled,
                "sensor_read_plan": effective.sensor_read_plan,
                "updated_at": effective.updated_at,
            },
            "ports": {
                "wind_speed": self.settings.wind_speed_port,
                "wind_direction": self.settings.wind_direction_port,
                "soil": self.settings.soil_port,
                "rain": self.settings.rain_port,
                "solar": self.settings.solar_port,
            },
            # Which device each sensor actually resolved to, and how confident we
            # are that it is that sensor. Sensors listed as unresolved publish
            # null on purpose.
            "identity": self.port_resolver.status(),
            "sensor_failures": dict(self._sensor_failures),
            "settings_cache": self.settings_cache.status(),
            "relays": self.relays.status(),
            "last_poll_at": self.last_poll_at,
            "last_success_at": self.last_success_at,
            "last_settings_at": self.last_settings_at,
            "last_error": self.last_error,
        }

    def _fallback_runtime_settings(self) -> StationRuntimeSettings:
        order = [name for name in self.settings.sensor_read_sequence if name in self.readers]
        return StationRuntimeSettings(
            poll_interval_seconds=max(1, int(self.settings.serial_poll_interval_seconds)),
            inter_read_delay_ms=max(0, int(self.settings.sensor_inter_read_delay_ms)),
            sensor_read_sequence=order,
            enabled={name: False for name in self.readers.keys()},
            sensor_read_plan={},
            forecast_latitude=None,
            forecast_longitude=None,
            updated_at=None,
        )

    def _runtime_log_payload(self, runtime: StationRuntimeSettings) -> dict[str, Any]:
        return {
            "poll_interval_seconds": runtime.poll_interval_seconds,
            "inter_read_delay_ms": runtime.inter_read_delay_ms,
            "read_order": runtime.sensor_read_sequence,
            "enabled": runtime.enabled,
            "sensor_read_plan": runtime.sensor_read_plan,
            "relay_groups": relay_groups_for_runtime(runtime),
            "updated_at": runtime.updated_at.isoformat() if runtime.updated_at else None,
        }

    def _runtime_log_signature_for(self, runtime: StationRuntimeSettings) -> tuple[Any, ...]:
        return (
            runtime.updated_at,
            runtime.poll_interval_seconds,
            runtime.inter_read_delay_ms,
            tuple(runtime.sensor_read_sequence),
            tuple(sorted(runtime.enabled.items())),
            tuple(
                sorted(
                    (key, tuple(sorted(value.items())))
                    for key, value in runtime.sensor_read_plan.items()
                )
            ),
        )

    def _log_runtime_settings(self, runtime: StationRuntimeSettings, *, source: str) -> None:
        signature = self._runtime_log_signature_for(runtime)
        if signature == self._runtime_log_signature:
            return
        self._runtime_log_signature = signature
        logger.info(
            "Station runtime settings loaded from %s for %s: %s",
            source,
            self.settings.device_id,
            self._runtime_log_payload(runtime),
        )

    def _load_runtime_settings(self) -> StationRuntimeSettings:
        """Current station settings, served from the shared TTL cache.

        Previously this opened a Session and ran two SELECTs (plus a possible
        COMMIT) on every call — and it was called once per second for the whole
        of every sleep. The cache collapses that to one cheap change-check per
        TTL, and keeps serving the last known-good value through a transient
        database outage instead of falling back to "everything disabled".
        """
        runtime = self.settings_cache.get()
        if runtime is None:
            runtime = self._runtime_settings or self._fallback_runtime_settings()
            source = "fallback"
        else:
            source = "database"

        self._runtime_settings = runtime
        self.last_settings_at = datetime.now(timezone.utc)
        self._log_runtime_settings(runtime, source=source)
        # Pending due times are recomputed here, not only at cycle start, so a
        # cadence edit in the app lands on the very next cycle.
        self._reconcile_sensor_schedule(runtime)
        self.relays.off_disabled(relay_groups_for_runtime(runtime))
        return runtime

    async def _sleep_with_runtime_checks(
        self,
        duration_seconds: float,
        runtime: StationRuntimeSettings,
    ) -> bool:
        """Sleep, waking early if station settings change.

        The wake-up granularity stays at SETTINGS_REFRESH_INTERVAL_SECONDS so a
        toggle in the app still takes effect within a second, but the check now
        hits the settings cache rather than the database.
        """
        remaining = max(0.0, duration_seconds)
        while self.running and remaining > 0:
            refresh_interval = max(
                0.25,
                float(self.settings.settings_refresh_interval_seconds),
            )
            chunk = min(refresh_interval, remaining)
            await asyncio.sleep(chunk)
            remaining -= chunk

            latest_runtime = self._load_runtime_settings()
            if latest_runtime != runtime:
                return True

        return False

    def _sensor_plan_item(self, runtime: StationRuntimeSettings, sensor_name: str) -> dict[str, Any] | None:
        if not runtime.sensor_read_plan:
            return None
        item = runtime.sensor_read_plan.get(sensor_name)
        if not item:
            return None
        return item

    def _sensor_interval_seconds(self, runtime: StationRuntimeSettings, sensor_name: str) -> int | None:
        item = self._sensor_plan_item(runtime, sensor_name)
        if item is None:
            return None
        try:
            reads_per_day = max(0, int(item.get("reads_per_day", 0)))
        except Exception:
            reads_per_day = 0
        if reads_per_day <= 0:
            return None
        return max(1, round(86400 / reads_per_day))

    def _effective_interval_seconds(self, runtime: StationRuntimeSettings, sensor_name: str) -> int:
        """Cadence actually used for this sensor, plan first, poll interval second."""
        interval_seconds = self._sensor_interval_seconds(runtime, sensor_name)
        if interval_seconds is None:
            interval_seconds = max(1, int(runtime.poll_interval_seconds))
        return max(1, int(interval_seconds))

    def _reconcile_sensor_schedule(self, runtime: StationRuntimeSettings) -> None:
        """Re-anchor pending due times whenever a sensor's cadence changes.

        This is the fix for "every relay follows the longest schedule". A due
        time was written once, as ``read_time + interval_at_that_moment``, and
        nothing ever revisited it. So after the station had run with a long
        cadence -- the 24-reads-per-day default a fresh settings row starts
        with, or a 2-hour setting the user tried earlier -- shortening a sensor
        to 30 minutes or 5 seconds in the app changed nothing until the *old*
        timer expired. Every relay kept ticking on the longest cadence that had
        ever been configured, which is exactly what the station sounded like.

        Re-anchoring against the last actual read means a shortened cadence
        takes effect on the next cycle, and a lengthened one stops an already
        overdue sensor from firing immediately.
        """
        now = datetime.now(timezone.utc)
        for sensor_name in self.readers:
            interval_seconds = self._effective_interval_seconds(runtime, sensor_name)
            previous = self._sensor_interval_seen.get(sensor_name)
            if previous == interval_seconds:
                continue
            self._sensor_interval_seen[sensor_name] = interval_seconds
            self._warn_if_cadence_unreachable(sensor_name, interval_seconds)
            if previous is None:
                # First time this sensor is seen: leave scheduling to
                # _sensor_is_due, which makes it due immediately.
                continue

            anchor = self._sensor_last_read_at.get(sensor_name, now)
            rescheduled = max(now, anchor + timedelta(seconds=interval_seconds))
            self._sensor_next_due_at[sensor_name] = rescheduled
            logger.info(
                "%s cadence changed %ss -> %ss; next read re-anchored to %s",
                sensor_name,
                previous,
                interval_seconds,
                rescheduled.isoformat(),
            )

    def _warn_if_cadence_unreachable(self, sensor_name: str, interval_seconds: int) -> None:
        """Say so when a configured cadence is faster than the relay allows.

        A relay group cannot cycle faster than its stabilize window, so a sensor
        set to 5 seconds behind a 30 second stabilize is really read every ~30
        seconds. Silently doing that looks like the schedule being ignored.
        """
        group = relay_group_for_sensor(sensor_name)
        if group is None or not self.relays.enabled:
            return
        floor = self.relays.stabilize_seconds
        if floor <= 0 or interval_seconds >= floor:
            self._unreachable_cadence_logged.discard(sensor_name)
            return
        if sensor_name in self._unreachable_cadence_logged:
            return
        self._unreachable_cadence_logged.add(sensor_name)
        logger.warning(
            "%s is scheduled every %ss but relay group '%s' needs %.0fs to power the "
            "sensor and let it settle, so it will be read about every %.0fs. Lower "
            "RELAY_MIN_STABILIZE_SECONDS/RELAY_SETTLE_SECONDS to go faster.",
            sensor_name,
            interval_seconds,
            group,
            floor,
            floor,
        )

    def _sensor_is_due(self, runtime: StationRuntimeSettings, sensor_name: str, now: datetime) -> bool:
        item = self._sensor_plan_item(runtime, sensor_name)
        if item is None:
            return False

        next_due = self._sensor_next_due_at.get(sensor_name)
        if next_due is None:
            self._sensor_next_due_at[sensor_name] = now
            return True
        return now >= next_due

    def _record_sensor_due(
        self,
        runtime: StationRuntimeSettings,
        sensor_name: str,
        now: datetime,
        *,
        read_attempted: bool = True,
    ) -> None:
        """Book the next read for this sensor. Must run for every due sensor.

        ``read_attempted=False`` is used for a sensor that was due but skipped
        (currently: still in failure backoff). Rescheduling it anyway is what
        stops it from staying permanently overdue -- an always-due sensor makes
        _next_sensor_due_seconds return 0, so the poller never sleeps, powers
        that relay group every cycle for nothing, and starves the sensors that
        are actually on a schedule.
        """
        interval_seconds = self._effective_interval_seconds(runtime, sensor_name)
        next_due = now + timedelta(seconds=interval_seconds)
        if read_attempted:
            self._sensor_last_read_at[sensor_name] = now
        else:
            # Don't push a fast sensor past the end of its backoff: retry as
            # soon as the backoff clears if that comes first.
            backoff_until = self._sensor_unavailable_until.get(sensor_name)
            if backoff_until is not None and backoff_until < next_due:
                next_due = backoff_until
        self._sensor_next_due_at[sensor_name] = max(next_due, now + timedelta(seconds=1))
        self._sensor_interval_seen[sensor_name] = interval_seconds

    def _legacy_selected_sensors(self, runtime: StationRuntimeSettings) -> list[str]:
        return [
            name
            for name in runtime.sensor_read_sequence
            if name in self.readers and runtime.enabled.get(name, False)
        ]

    def _group_ordered_sensors(self, ordered_sensors: list[str]) -> list[tuple[str | None, list[str]]]:
        grouped: dict[str | None, list[str]] = {}
        order: list[str | None] = []
        for sensor_name in ordered_sensors:
            group = relay_group_for_sensor(sensor_name)
            if group not in grouped:
                grouped[group] = []
                order.append(group)
            grouped[group].append(sensor_name)
        return [(group, grouped[group]) for group in order]

    def _next_sensor_due_seconds(self, runtime: StationRuntimeSettings, now: datetime) -> float:
        if not runtime.sensor_read_plan:
            return max(1.0, float(runtime.poll_interval_seconds))

        next_due: float | None = None
        for name, item in runtime.sensor_read_plan.items():
            if not runtime.enabled.get(name, False):
                continue
            if name == "solar" and self.solar_cache is not None:
                continue
            due_at = self._sensor_next_due_at.get(name)
            if due_at is None:
                return 0.0
            remaining = (due_at - now).total_seconds()
            if remaining <= 0:
                return 0.0
            if next_due is None or remaining < next_due:
                next_due = remaining
        return 60.0 if next_due is None else max(1.0, next_due)

    def resolve_identities(self, *, reason: str = "startup") -> None:
        """Re-run sensor identity resolution. Never raises."""
        try:
            self.port_resolver.resolve()
            self._identity_resolved_at = datetime.now(timezone.utc)
            unresolved = [
                name
                for name in self.sensor_baudrates
                if self.port_resolver.device_for(name) is None
            ]
            if unresolved:
                logger.warning(
                    "Sensor identity (%s): %s will publish null until identified. "
                    "Run: python -m app.tools.ports doctor",
                    reason,
                    ", ".join(sorted(unresolved)),
                )
            else:
                logger.info("Sensor identity (%s): all sensors identified", reason)
        except Exception as exc:
            logger.warning("Sensor identity resolution failed (%s): %s", reason, exc)

    def _maybe_recheck_identities(self) -> None:
        """Periodically re-resolve so a hot-plug is picked up without a restart."""
        interval = float(self.settings.sensor_identity_recheck_seconds or 0)
        if interval <= 0:
            return
        last = self._identity_resolved_at
        if last is not None and (datetime.now(timezone.utc) - last).total_seconds() < interval:
            return
        self.resolve_identities(reason="periodic recheck")

    def _port_for(self, sensor_name: str) -> str | None:
        """Device to read, or None when identity is not confirmed.

        Returning None here is what stops a mis-enumerated adapter from being
        published under the wrong sensor's name.
        """
        return self.port_resolver.device_for(sensor_name)

    def _open_instrument(self, sensor_name: str) -> minimalmodbus.Instrument | None:
        port = self._port_for(sensor_name)
        if port is None:
            assignment = self.port_resolver.assignments.get(sensor_name)
            detail = "identity not confirmed" if assignment is None else assignment.detail
            self._mark_sensor_unavailable(sensor_name, detail)
            return None
        return create_instrument(port, self.sensor_baudrates[sensor_name], sensor_name)

    def _reset_instrument(self, sensor_name: str) -> minimalmodbus.Instrument | None:
        self._close_instrument(sensor_name)
        port = self._port_for(sensor_name)
        logger.info("Reopening serial instrument for %s on %s", sensor_name, port)
        instrument = self._open_instrument(sensor_name)
        self.instruments[sensor_name] = instrument
        if instrument is None:
            self._mark_sensor_unavailable(sensor_name, "serial instrument could not be opened")
        else:
            self._sensor_unavailable_until.pop(sensor_name, None)
        return instrument

    def _close_instrument(self, sensor_name: str) -> None:
        instrument = self.instruments.get(sensor_name)
        self.instruments[sensor_name] = None
        if instrument is None:
            return
        try:
            if instrument.serial and instrument.serial.is_open:
                instrument.serial.close()
        except Exception:
            # A vanished USB device raises on close; nothing useful to do.
            pass

    def _get_instrument(self, sensor_name: str) -> minimalmodbus.Instrument | None:
        if self._sensor_is_in_backoff(sensor_name):
            return None

        instrument = self.instruments.get(sensor_name)
        if instrument is not None:
            return instrument

        instrument = self._open_instrument(sensor_name)
        self.instruments[sensor_name] = instrument
        if instrument is None:
            self._mark_sensor_unavailable(sensor_name, "serial instrument could not be opened")
        else:
            self._sensor_unavailable_until.pop(sensor_name, None)
        return instrument

    def _sensor_is_in_backoff(self, sensor_name: str) -> bool:
        until = self._sensor_unavailable_until.get(sensor_name)
        if until is None:
            return False
        if datetime.now(timezone.utc) < until:
            return True
        self._sensor_unavailable_until.pop(sensor_name, None)
        return False

    def _mark_sensor_unavailable(self, sensor_name: str, reason: str) -> None:
        now = datetime.now(timezone.utc)
        previous_retry_at = self._sensor_unavailable_until.get(sensor_name)
        retry_at = now + timedelta(seconds=SENSOR_UNAVAILABLE_BACKOFF_SECONDS)
        self._sensor_unavailable_until[sensor_name] = retry_at
        if previous_retry_at is None or previous_retry_at <= now:
            logger.warning(
                "%s unavailable: %s; retrying after %.0f second(s)",
                sensor_name,
                reason,
                SENSOR_UNAVAILABLE_BACKOFF_SECONDS,
            )

    def _record_success(self, sensor_name: str) -> None:
        self._sensor_failures[sensor_name] = 0
        self._sensor_unavailable_until.pop(sensor_name, None)

    def _record_failure(self, sensor_name: str, reason: str) -> None:
        """Count a failure and only back off once the threshold is crossed.

        A single dropped frame is normal on RS-485; backing off immediately made
        transient noise look like a dead sensor.
        """
        count = self._sensor_failures.get(sensor_name, 0) + 1
        self._sensor_failures[sensor_name] = count
        threshold = max(1, int(self.settings.sensor_failure_threshold))
        if count >= threshold:
            self._mark_sensor_unavailable(
                sensor_name, f"{reason} ({count} consecutive failures)"
            )
        else:
            logger.info(
                "%s read failed (%s/%s): %s", sensor_name, count, threshold, reason
            )

    def _read_with_reconnect(self, sensor_name: str, reader):
        """Blocking read for one sensor. Runs in a worker thread.

        Guarded by a per-port lock so a read abandoned by the async timeout
        cannot be running concurrently with the next one on the same device.

        Every attempt after the first reopens the port and waits
        SENSOR_RETRY_DELAY_MS first. That retry budget is what lets the second
        sensor on a shared relay succeed: wind speed and wind direction are
        powered by the same pin, and the direction sensor is often still
        settling when the speed read finishes.
        """
        lock = self._sensor_locks[sensor_name]
        if not lock.acquire(blocking=False):
            logger.warning("%s skipped: previous read still in flight", sensor_name)
            return None

        attempts = 1 + max(0, int(self.settings.sensor_read_retries))
        retry_delay = max(0.0, float(self.settings.sensor_retry_delay_ms) / 1000.0)
        # Leave headroom inside the caller's hard deadline so the last attempt
        # reports a real failure instead of being killed mid-transaction.
        deadline = time.monotonic() + max(1.0, float(self.settings.sensor_read_timeout_seconds)) * 0.8
        last_reason = "read returned no data"

        try:
            for attempt in range(1, attempts + 1):
                if attempt == 1:
                    instrument = self._get_instrument(sensor_name)
                else:
                    if time.monotonic() + retry_delay >= deadline:
                        logger.info(
                            "%s out of retry budget after attempt %s/%s", sensor_name, attempt - 1, attempts
                        )
                        break
                    if retry_delay > 0:
                        time.sleep(retry_delay)
                    instrument = self._reset_instrument(sensor_name)
                if instrument is None:
                    # Identity unconfirmed or the port would not open;
                    # _get_instrument/_reset_instrument already set the backoff.
                    return None

                try:
                    value = reader(instrument)
                except Exception as exc:
                    last_reason = f"read raised {exc}"
                    value = None
                    logger.warning(
                        "%s read attempt %s/%s failed: %s", sensor_name, attempt, attempts, exc
                    )

                if value is not None:
                    self._record_success(sensor_name)
                    if attempt > 1:
                        logger.info("%s recovered on attempt %s/%s", sensor_name, attempt, attempts)
                        # Drop the handle so the next cycle reopens against the
                        # freshly resolved device node.
                        self._close_instrument(sensor_name)
                    return value

                if attempt < attempts:
                    logger.info(
                        "%s read attempt %s/%s returned no data; reopening port and retrying",
                        sensor_name,
                        attempt,
                        attempts,
                    )

            self._record_failure(sensor_name, f"{last_reason} after {attempts} attempt(s)")
            self._close_instrument(sensor_name)
            return None
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("%s read wrapper failed: %s", sensor_name, exc)
            return None
        finally:
            lock.release()

    async def _read_sensor(self, sensor_name: str):
        """Await one sensor read off the event loop, with a hard deadline.

        This is the fix for "one sensor stops responding and the whole system
        goes down": minimalmodbus is blocking, so a stuck port used to freeze
        the event loop and with it every HTTP request uvicorn was serving.
        """
        timeout = max(1.0, float(self.settings.sensor_read_timeout_seconds))
        try:
            return await asyncio.wait_for(
                asyncio.to_thread(self.readers[sensor_name]),
                timeout=timeout,
            )
        except asyncio.TimeoutError:
            self._record_failure(sensor_name, f"read exceeded {timeout:.1f}s deadline")
            logger.warning(
                "%s read timed out after %.1fs; other sensors will continue",
                sensor_name,
                timeout,
            )
            return None
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            self._record_failure(sensor_name, f"read raised {exc}")
            logger.warning("%s read raised; other sensors will continue: %s", sensor_name, exc)
            return None

    async def _pause_between_reads(self, inter_read_delay_ms: int) -> None:
        delay_seconds = max(0.0, float(inter_read_delay_ms) / 1000.0)
        if delay_seconds > 0:
            await asyncio.sleep(delay_seconds)

    async def build_payload(self, runtime: StationRuntimeSettings, *, advisory_active: bool = False) -> ReadingPayload | None:
        results: dict[str, Any] = {
            "wind_speed": None,
            "wind_direction": (None, None),
            "soil": {"moist": None, "temp": None, "ec": None, "n": None, "p": None, "k": None, "ph": None},
            "rain": None,
            "solar": None,
        }

        if runtime.sensor_read_plan:
            due_items: list[tuple[int, int, int, str]] = []
            now = datetime.now(timezone.utc)
            for index, name in enumerate(runtime.sensor_read_sequence):
                if name not in self.readers or not runtime.enabled.get(name, False):
                    continue
                if name == "solar" and self.solar_cache is not None:
                    continue
                item = runtime.sensor_read_plan.get(name)
                if item is None:
                    continue
                if not self._sensor_is_due(runtime, name, now):
                    continue
                priority = item.get("priority")
                try:
                    priority_value = int(priority) if priority is not None else 999
                except Exception:
                    priority_value = 999
                # Tie-break on cadence so a fast sensor is not queued behind a
                # slow one -- and behind its 30s relay stabilize -- on the
                # cycles where both happen to come due together.
                interval = self._effective_interval_seconds(runtime, name)
                due_items.append((priority_value, interval, index, name))
            ordered_sensors = [name for *_, name in sorted(due_items)]
        else:
            ordered_sensors = self._legacy_selected_sensors(runtime)

        if not ordered_sensors:
            return None

        if self.solar_cache is not None:
            ordered_sensors = [name for name in ordered_sensors if name != "solar"]

        if not ordered_sensors:
            return None

        # Sensors already in failure backoff are dropped here, before grouping,
        # so their relay group is not powered (and 30s of stabilize burned) for
        # a read that will be skipped anyway. They are still rescheduled, or
        # they stay permanently overdue and stop the poller from ever sleeping.
        now = datetime.now(timezone.utc)
        ready_sensors: list[str] = []
        for sensor_name in ordered_sensors:
            if self._sensor_is_in_backoff(sensor_name):
                logger.info("%s skipped this cycle because it is in retry backoff", sensor_name)
                if not advisory_active:
                    self._record_sensor_due(runtime, sensor_name, now, read_attempted=False)
                continue
            ready_sensors.append(sensor_name)
        ordered_sensors = ready_sensors

        if not ordered_sensors:
            return None

        logger.info(
            "Sensor read cycle for %s: advisory_active=%s ordered_sensors=%s enabled=%s",
            self.settings.device_id,
            advisory_active,
            ordered_sensors,
            runtime.enabled,
        )

        grouped_sensors = self._group_ordered_sensors(ordered_sensors)
        for group_index, (relay_group, sensors) in enumerate(grouped_sensors):
            pin = None if relay_group is None else self.relays.pins.get(relay_group)
            logger.info(
                "Sensor relay group start: relay=%s pin=%s sensors=%s",
                relay_group,
                pin,
                sensors,
            )
            relay_started = self.relays.on(relay_group)
            try:
                if relay_started and self.relays.stabilize_seconds > 0:
                    logger.info(
                        "Sensor relay group stabilizing: relay=%s pin=%s seconds=%.2f",
                        relay_group,
                        pin,
                        self.relays.stabilize_seconds,
                    )
                    await asyncio.sleep(self.relays.stabilize_seconds)
                for sensor_index, sensor_name in enumerate(sensors):
                    logger.info("%s read started", sensor_name)
                    try:
                        results[sensor_name] = await self._read_sensor(sensor_name)
                    except asyncio.CancelledError:
                        raise
                    except Exception as exc:
                        logger.warning("%s read wrapper failed; other sensors will continue: %s", sensor_name, exc)
                        results[sensor_name] = None
                    logger.info("%s read result: %s", sensor_name, results[sensor_name])
                    if not advisory_active:
                        self._record_sensor_due(runtime, sensor_name, now)
                    is_last_sensor = sensor_index >= len(sensors) - 1
                    if not is_last_sensor:
                        await self._pause_between_reads(runtime.inter_read_delay_ms)
            finally:
                self.relays.off(relay_group)
                logger.info(
                    "Sensor relay group end: relay=%s pin=%s sensors=%s",
                    relay_group,
                    pin,
                    sensors,
                )
            if group_index < len(grouped_sensors) - 1:
                await self._pause_between_reads(runtime.inter_read_delay_ms)

        wind_speed = results.get("wind_speed")

        wind_direction_value = results.get("wind_direction")
        if isinstance(wind_direction_value, tuple) and len(wind_direction_value) == 2:
            wind_deg, wind_dir = wind_direction_value
        else:
            wind_deg, wind_dir = None, None

        soil = results.get("soil")
        if not isinstance(soil, dict):
            soil = empty_soil_reading()

        rainfall = results.get("rain")
        solar = (
            self.solar_cache.value
            if self.solar_cache is not None and runtime.enabled.get("solar", False)
            else results.get("solar")
        )

        return ReadingPayload(
            ws=wind_speed,
            wd_deg=wind_deg,
            wd_dir=wind_dir,
            moist=soil.get("moist"),
            temp=soil.get("temp"),
            ec=soil.get("ec"),
            n=soil.get("n"),
            p=soil.get("p"),
            k=soil.get("k"),
            ph=soil.get("ph"),
            rain=rainfall,
            solar=solar,
        )

    async def start(self) -> None:
        if not self.settings.serial_reader_enabled or self.running:
            return
        self.running = True
        if self.settings.serial_console_output_enabled:
            self.live = Live(console=console, refresh_per_second=4, screen=True, transient=False)
            self.live.start()
        self.task = asyncio.create_task(self._run_loop())
        logger.info("Serial sensor poller started for device %s", self.settings.device_id)

    async def stop(self) -> None:
        self.running = False
        if self.task:
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass
            self.task = None
        if self.live:
            self.live.stop()
            self.live = None
        for sensor_name in list(self.instruments.keys()):
            self._close_instrument(sensor_name)
        self.relays.cleanup()

    async def _run_loop(self) -> None:
        startup_delay = max(0, self.settings.serial_startup_delay_seconds)
        loop = asyncio.get_running_loop()

        if startup_delay > 0:
            logger.info("Waiting %s second(s) before first sensor poll.", startup_delay)
            await asyncio.sleep(startup_delay)

        # Identify which adapter is which before the first read. Probing is
        # blocking, so keep it off the event loop. Skipped when startup already
        # resolved (see the app lifespan).
        if self._identity_resolved_at is None:
            await asyncio.to_thread(self.resolve_identities, reason="startup")

        while self.running:
            await asyncio.to_thread(self._maybe_recheck_identities)
            runtime = self._load_runtime_settings()
            interval = max(1, int(runtime.poll_interval_seconds))
            advisory_active = False

            cycle_started_at = loop.time()
            try:
                self.last_poll_at = datetime.now(timezone.utc)
                payload = await self.build_payload(runtime, advisory_active=advisory_active)
                if payload is None:
                    remaining_sleep = self._next_sensor_due_seconds(runtime, self.last_poll_at)
                    settings_changed = await self._sleep_with_runtime_checks(remaining_sleep, runtime)
                    if settings_changed:
                        continue
                    continue
                request = IngestRequest(
                    device_id=self.settings.device_id,
                    station_name=self.settings.station_name,
                    recorded_at=self.last_poll_at,
                    data=payload,
                )

                db = SessionLocal()
                try:
                    reading = create_reading_sync(db, request)
                finally:
                    db.close()

                self.last_success_at = datetime.now(timezone.utc)
                self.last_error = None
                if self.settings.serial_console_output_enabled and self.live:
                    self.live.update(
                        build_terminal_dashboard(
                            self.settings.device_id,
                            self.settings.station_name,
                            payload,
                            self.last_poll_at,
                            interval,
                        ),
                        refresh=True,
                    )
                await run_broadcast(
                    self.settings.device_id,
                    {"type": "reading.created", "payload": reading.model_dump(mode="json")},
                )
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                self.last_error = str(exc)
                logger.exception("Serial sensor polling failed: %s", exc)
                if self.settings.serial_console_output_enabled and self.live:
                    self.live.update(
                        Panel(
                            Text(f"Serial polling error: {exc}", style="bold white on red", justify="center"),
                            title="[bold]Sensor Runtime Error[/bold]",
                            border_style="red",
                            padding=(2, 2),
                        ),
                        refresh=True,
                    )

            if runtime.sensor_read_plan:
                remaining_sleep = self._next_sensor_due_seconds(runtime, datetime.now(timezone.utc))
            else:
                remaining_sleep = interval - (loop.time() - cycle_started_at)
            if remaining_sleep > 0:
                settings_changed = await self._sleep_with_runtime_checks(remaining_sleep, runtime)
                if settings_changed:
                    continue
