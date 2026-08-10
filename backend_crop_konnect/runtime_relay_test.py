from __future__ import annotations

import argparse
import logging
import signal
import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

import minimalmodbus
import serial

from app.config import Settings, get_settings
from app.gpio_relay import GpioOutput, create_gpio_output
from app.station_settings import StationRuntimeSettings, load_runtime_settings


logger = logging.getLogger("runtime_relay_test")

SLAVE_ID = 1
SERIAL_TIMEOUT = 1.0
BAUD_WIND = 4800
BAUD_SOIL = 9600
BAUD_RAIN = 4800
BAUD_SOLAR = 4800
UNIVERSAL_DIRS = [
    "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
    "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
]


class RelayController:
    def __init__(self, settings: Settings) -> None:
        self.enabled = bool(settings.relay_control_enabled)
        self.active_low = bool(settings.relay_active_low)
        self.settle_seconds = max(0.0, float(settings.relay_settle_seconds))
        self.pins = {
            "wind": settings.relay_wind_pin,
            "soil": settings.relay_soil_pin,
            "rain": settings.relay_rain_pin,
            "solar": settings.relay_solar_pin,
        }
        self._gpio: GpioOutput | None = None
        self._active: set[str] = set()

        if not self.enabled:
            logger.warning("Relay control is disabled. Set RELAY_CONTROL_ENABLED=true to test GPIO relays.")
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

    def on(self, group: str) -> None:
        if not self.enabled or self._gpio is None:
            return
        pin = self.pins.get(group)
        if pin is None or group in self._active:
            return
        self._gpio.output(pin, self._on_value())
        self._active.add(group)
        logger.info("Relay %s ON on GPIO pin %s", group, pin)

    def off(self, group: str) -> None:
        if not self.enabled or self._gpio is None:
            return
        pin = self.pins.get(group)
        if pin is None or group not in self._active:
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

    def pulse(self, group: str, seconds: float) -> None:
        pin = self.pins.get(group)
        logger.info("PULSE START relay=%s pin=%s seconds=%.2f", group, pin, seconds)
        self.on(group)
        time.sleep(max(0.0, seconds))
        self.off(group)
        logger.info("PULSE END relay=%s pin=%s", group, pin)

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
            "pins": self.pins,
            "active": sorted(self._active),
        }


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
        if sensor_name == "solar":
            instrument.clear_buffers_before_each_transaction = False
            instrument.close_port_after_each_call = False
        else:
            instrument.clear_buffers_before_each_transaction = True
            instrument.close_port_after_each_call = True
        return instrument
    except Exception as exc:
        logger.warning("Failed to configure %s port %s: %s", sensor_name or "sensor", port, exc)
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


def read_wind_direction(instrument: minimalmodbus.Instrument | None) -> tuple[float | None, str | None]:
    gear = safe_read_register(instrument, register_address=0, decimals=0, function_code=3, sensor_name="wind_dir")
    if gear is None:
        return None, None

    try:
        gear_index = max(0, min(15, int(gear)))
        return gear_index * 22.5, UNIVERSAL_DIRS[gear_index]
    except Exception as exc:
        logger.warning("wind_dir conversion failed: %s", exc)
        return None, None


def read_soil(instrument: minimalmodbus.Instrument | None) -> dict[str, float | None]:
    registers = safe_read_registers(instrument, register_address=0, count=7, function_code=3, sensor_name="soil")
    if not registers or len(registers) != 7:
        return {"moist": None, "temp": None, "ec": None, "n": None, "p": None, "k": None, "ph": None}

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
        return {"moist": None, "temp": None, "ec": None, "n": None, "p": None, "k": None, "ph": None}


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


@dataclass(frozen=True)
class SensorDefinition:
    relay_group: str
    port: str | None
    baudrate: int
    reader: Callable[[minimalmodbus.Instrument | None], Any]


def sensor_definitions(settings: Settings) -> dict[str, SensorDefinition]:
    return {
        "wind_speed": SensorDefinition("wind", settings.wind_speed_port, BAUD_WIND, read_wind_speed),
        "wind_direction": SensorDefinition("wind", settings.wind_direction_port, BAUD_WIND, read_wind_direction),
        "soil": SensorDefinition("soil", settings.soil_port, BAUD_SOIL, read_soil),
        "rain": SensorDefinition("rain", settings.rain_port, BAUD_RAIN, read_rain),
        "solar": SensorDefinition("solar", settings.solar_port, BAUD_SOLAR, read_solar_radiation),
    }


def relay_groups_for_runtime(runtime: StationRuntimeSettings) -> dict[str, bool]:
    return {
        "wind": bool(runtime.enabled.get("wind_speed", False) or runtime.enabled.get("wind_direction", False)),
        "soil": bool(runtime.enabled.get("soil", False)),
        "rain": bool(runtime.enabled.get("rain", False)),
        "solar": bool(runtime.enabled.get("solar", False)),
    }


def selected_sensors(runtime: StationRuntimeSettings, definitions: dict[str, SensorDefinition]) -> list[str]:
    return [
        name
        for name in runtime.sensor_read_sequence
        if name in definitions and runtime.enabled.get(name, False)
    ]


def skipped_sensors(runtime: StationRuntimeSettings, definitions: dict[str, SensorDefinition]) -> list[str]:
    return [
        name
        for name in runtime.sensor_read_sequence
        if name in definitions and not runtime.enabled.get(name, False)
    ]


def sensor_interval_seconds(runtime: StationRuntimeSettings, sensor_name: str) -> float:
    item = runtime.sensor_read_plan.get(sensor_name) or {}
    try:
        reads_per_day = max(0, int(item.get("reads_per_day", 0)))
    except Exception:
        reads_per_day = 0
    if reads_per_day > 0:
        return max(1.0, round(86400 / reads_per_day))
    return max(1.0, float(runtime.poll_interval_seconds))


def due_sensors(
    runtime: StationRuntimeSettings,
    definitions: dict[str, SensorDefinition],
    next_due_at: dict[str, float],
    now: float,
    force: bool = False,
) -> list[str]:
    due: list[str] = []
    for name in selected_sensors(runtime, definitions):
        if force or now >= next_due_at.get(name, 0.0):
            due.append(name)
    return due


def due_sensor_groups(
    runtime: StationRuntimeSettings,
    definitions: dict[str, SensorDefinition],
    next_due_at: dict[str, float],
    now: float,
    force: bool = False,
) -> dict[str, list[str]]:
    groups: dict[str, list[str]] = {}
    for sensor_name in due_sensors(runtime, definitions, next_due_at, now, force=force):
        group = definitions[sensor_name].relay_group
        groups.setdefault(group, []).append(sensor_name)
    return groups


def runtime_signature(runtime: StationRuntimeSettings) -> tuple[Any, ...]:
    return (
        runtime.updated_at,
        tuple(runtime.sensor_read_sequence),
        tuple(sorted(runtime.enabled.items())),
        runtime.poll_interval_seconds,
        runtime.inter_read_delay_ms,
        tuple(sorted((key, tuple(sorted(value.items()))) for key, value in runtime.sensor_read_plan.items())),
    )


def load_settings_from_db(settings: Settings) -> StationRuntimeSettings:
    from app.db import SessionLocal

    db = SessionLocal()
    try:
        return load_runtime_settings(
            db,
            device_id=settings.device_id,
            station_name=settings.station_name,
            env=settings,
        )
    finally:
        db.close()


def open_instrument(
    name: str,
    definition: SensorDefinition,
    instruments: dict[str, minimalmodbus.Instrument | None],
) -> minimalmodbus.Instrument | None:
    instrument = instruments.get(name)
    if instrument is not None:
        return instrument
    instrument = create_instrument(definition.port, definition.baudrate, name)
    instruments[name] = instrument
    if instrument is None:
        logger.warning("%s port is not available or failed to open: %s", name, definition.port)
    return instrument


def close_instruments(instruments: dict[str, minimalmodbus.Instrument | None]) -> None:
    for instrument in instruments.values():
        if instrument is None:
            continue
        try:
            if instrument.serial and instrument.serial.is_open:
                instrument.serial.close()
        except Exception:
            pass


def read_enabled_sensors(
    runtime: StationRuntimeSettings,
    definitions: dict[str, SensorDefinition],
    instruments: dict[str, minimalmodbus.Instrument | None],
    sensors: list[str] | None = None,
) -> dict[str, Any]:
    results: dict[str, Any] = {}
    enabled = sensors if sensors is not None else selected_sensors(runtime, definitions)
    disabled = skipped_sensors(runtime, definitions)

    logger.info("READ CYCLE enabled=%s disabled=%s", enabled, disabled)
    for name in enabled:
        definition = definitions[name]
        logger.info("%s read started on %s", name, definition.port)
        try:
            instrument = open_instrument(name, definition, instruments)
            results[name] = definition.reader(instrument)
            logger.info("%s read result: %s", name, results[name])
        except Exception as exc:
            results[name] = None
            logger.exception("%s read failed; continuing other sensors: %s", name, exc)
    return results


def read_sensor_groups(
    runtime: StationRuntimeSettings,
    definitions: dict[str, SensorDefinition],
    instruments: dict[str, minimalmodbus.Instrument | None],
    relays: RelayController,
    groups: dict[str, list[str]],
) -> dict[str, Any]:
    results: dict[str, Any] = {}
    for group, sensors in groups.items():
        pin = relays.pins.get(group)
        logger.info("READ GROUP START relay=%s pin=%s sensors=%s", group, pin, sensors)
        relays.on(group)
        try:
            if relays.settle_seconds > 0:
                time.sleep(relays.settle_seconds)
            results.update(
                read_enabled_sensors(
                    runtime,
                    definitions,
                    instruments,
                    sensors=sensors,
                )
            )
        finally:
            relays.off(group)
            logger.info("READ GROUP END relay=%s pin=%s", group, pin)
    return results


def log_runtime_settings(settings: Settings, runtime: StationRuntimeSettings, relay_groups: dict[str, bool]) -> None:
    logger.info(
        "DB SETTINGS device=%s enabled=%s relay_groups=%s read_order=%s poll_interval=%ss updated_at=%s",
        settings.device_id,
        runtime.enabled,
        relay_groups,
        runtime.sensor_read_sequence,
        runtime.poll_interval_seconds,
        runtime.updated_at,
    )
    if runtime.sensor_read_plan:
        logger.info("DB SENSOR PLAN %s", runtime.sensor_read_plan)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Runtime relay and RS485 test loop driven by Supabase station settings.",
    )
    parser.add_argument(
        "--read-interval",
        type=float,
        default=None,
        help="Seconds between read cycles. Default uses DB poll_interval_seconds.",
    )
    parser.add_argument(
        "--settings-interval",
        type=float,
        default=None,
        help="Seconds between Supabase settings refreshes. Default uses SETTINGS_REFRESH_INTERVAL_SECONDS.",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Load DB settings, sync relays, read enabled sensors once, then exit.",
    )
    parser.add_argument(
        "--relay-only",
        action="store_true",
        help="Only sync relays from DB settings. Do not open serial ports or read sensors.",
    )
    parser.add_argument(
        "--pulse-seconds",
        type=float,
        default=1.0,
        help="Relay ON duration for --relay-only pulse simulation.",
    )
    parser.add_argument(
        "--no-migrate",
        action="store_true",
        help="Do not run lightweight schema migration checks before starting.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    settings = get_settings()
    definitions = sensor_definitions(settings)
    relays = RelayController(settings)
    instruments: dict[str, minimalmodbus.Instrument | None] = {}
    running = True

    def stop(_: int, __: Any) -> None:
        nonlocal running
        running = False

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    logger.info("Runtime relay test started for device=%s station=%s", settings.device_id, settings.station_name)
    logger.info("Database URL configured: %s", settings.database_url)
    logger.info("Relay status at start: %s", relays.status())
    logger.info(
        "Ports: wind_speed=%s wind_direction=%s soil=%s rain=%s solar=%s",
        settings.wind_speed_port,
        settings.wind_direction_port,
        settings.soil_port,
        settings.rain_port,
        settings.solar_port,
    )

    if not args.no_migrate:
        from app.db import Base, engine
        from app.schema_migrations import ensure_runtime_schema

        Base.metadata.create_all(bind=engine)
        ensure_runtime_schema(engine)

    last_signature: tuple[Any, ...] | None = None
    next_due_at: dict[str, float] = {}

    try:
        while running:
            runtime = load_settings_from_db(settings)
            desired_relays = relay_groups_for_runtime(runtime)
            relays.off_disabled(desired_relays)

            signature = runtime_signature(runtime)
            if signature != last_signature:
                log_runtime_settings(settings, runtime, desired_relays)
                if args.relay_only:
                    logger.info(
                        "RELAY ONLY MODE active. Serial reads are skipped. enabled=%s disabled=%s",
                        selected_sensors(runtime, definitions),
                        skipped_sensors(runtime, definitions),
                )
                last_signature = signature
                next_due_at.clear()

            now = time.monotonic()
            groups_to_process = due_sensor_groups(
                runtime,
                definitions,
                next_due_at,
                now,
                force=args.once,
            )
            if args.relay_only:
                for group, sensors in groups_to_process.items():
                    relays.pulse(group, args.pulse_seconds)
                    for sensor_name in sensors:
                        read_interval = args.read_interval
                        if read_interval is None:
                            read_interval = sensor_interval_seconds(runtime, sensor_name)
                        next_due_at[sensor_name] = time.monotonic() + read_interval
            elif groups_to_process:
                read_sensor_groups(
                    runtime,
                    definitions,
                    instruments,
                    relays,
                    groups_to_process,
                )
                for sensors in groups_to_process.values():
                    for sensor_name in sensors:
                        read_interval = args.read_interval
                        if read_interval is None:
                            read_interval = sensor_interval_seconds(runtime, sensor_name)
                        next_due_at[sensor_name] = time.monotonic() + read_interval
                        if runtime.inter_read_delay_ms > 0:
                            time.sleep(runtime.inter_read_delay_ms / 1000)

            if args.once:
                break

            settings_interval = args.settings_interval
            if settings_interval is None:
                settings_interval = max(0.25, float(settings.settings_refresh_interval_seconds))
            time.sleep(settings_interval)
    finally:
        logger.info("Stopping runtime relay test; turning relays off and closing serial ports.")
        relays.cleanup()
        close_instruments(instruments)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
