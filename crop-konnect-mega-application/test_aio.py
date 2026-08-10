#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Integrated Weather Station + Solar Radiation Reader
---------------------------------------------------
Reads:
- Wind Speed
- Wind Direction
- Soil (moisture, temperature, EC, N, P, K, pH)
- Rainfall
- Solar Radiation

Uploads to Firebase Realtime Database.

Features:
- USB auto-detection using fixed Linux USB LOCATION paths
- Manual fallback port support
- Clean structured logging
- Safe Modbus reads
- Independent sensor failure handling
- Professional CLI dashboard output
"""

import json
import time
import logging
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Dict, Optional, Tuple, Any

import minimalmodbus
import serial
import serial.tools.list_ports
import firebase_admin
from firebase_admin import credentials, db


# ============================================================
# CONFIG
# ============================================================

SERVICE_ACCOUNT = "services.json"
DATABASE_URL = "https://green-bot-d7200-default-rtdb.firebaseio.com/"
DEVICE_ID = "RPAWTEX"

WIFI_SSID = "TAPWTEX"
WIFI_PASS = "rpawtexabc"

SLAVE_ID = 1
SERIAL_TIMEOUT = 1.0
POLL_INTERVAL_SECONDS = 5

# Default baud rates
BAUD_WIND = 4800
BAUD_SOIL = 9600
BAUD_RAIN = 4800
BAUD_SOLAR = 4800

UNIVERSAL_DIRS = [
    "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
    "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"
]

STYLE_SUFFIX = "ESS Crop Konnet"


# ============================================================
# ANSI STYLING
# ============================================================

class C:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"

    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    CYAN = "\033[36m"
    MAGENTA = "\033[35m"
    WHITE = "\033[37m"


def color_text(text: str, color: str, bold: bool = False) -> str:
    prefix = color
    if bold:
        prefix += C.BOLD
    return f"{prefix}{text}{C.RESET}"


# ============================================================
# SENSOR CONFIG
# ============================================================

@dataclass(frozen=True)
class SensorConfig:
    name: str
    baudrate: int
    location_keywords: Tuple[str, ...] = ()
    manual_port: Optional[str] = None


SENSOR_CONFIGS: Dict[str, SensorConfig] = {
    "wind_speed": SensorConfig(
        name="wind_speed",
        baudrate=BAUD_WIND,
        location_keywords=("LOCATION=1-1.1", "1-1.1"),
        manual_port="/dev/ttyUSB1",
    ),
    "wind_dir": SensorConfig(
        name="wind_dir",
        baudrate=BAUD_WIND,
        location_keywords=("LOCATION=1-1.2", "1-1.2"),
        manual_port="/dev/ttyUSB2",
    ),
    "soil": SensorConfig(
        name="soil",
        baudrate=BAUD_SOIL,
        location_keywords=("LOCATION=1-1.3", "1-1.3"),
        manual_port="/dev/ttyUSB0",
    ),
    "rain": SensorConfig(
        name="rain",
        baudrate=BAUD_RAIN,
        location_keywords=("LOCATION=1-1.4.2", "1-1.4.2"),
        manual_port="/dev/ttyUSB4",
    ),
    "solar": SensorConfig(
        name="solar",
        baudrate=BAUD_SOLAR,
        location_keywords=("LOCATION=1-1.4.3", "1-1.4.3"),
        manual_port="/dev/ttyUSB3",
    ),
}


# ============================================================
# LOGGING
# ============================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)


# ============================================================
# WIFI
# ============================================================

def connect_wifi() -> bool:
    """Attempt Wi-Fi connection using nmcli."""
    try:
        logging.info("Connecting to Wi-Fi SSID: %s", WIFI_SSID)
        result = subprocess.run(
            ["nmcli", "dev", "wifi", "connect", WIFI_SSID, "password", WIFI_PASS],
            capture_output=True,
            text=True,
            timeout=20
        )

        if result.returncode == 0:
            logging.info("Wi-Fi connected successfully.")
            return True

        stderr = result.stderr.strip() if result.stderr else "Unknown nmcli error"
        logging.warning("Wi-Fi connection may have failed: %s", stderr)
        return False

    except Exception as e:
        logging.error("Wi-Fi connection error: %s", e)
        return False


# ============================================================
# FIREBASE
# ============================================================

def init_firebase() -> bool:
    """Initialize Firebase Admin SDK."""
    try:
        if not firebase_admin._apps:
            cred = credentials.Certificate(SERVICE_ACCOUNT)
            firebase_admin.initialize_app(cred, {"databaseURL": DATABASE_URL})

        logging.info("Firebase Realtime DB initialized.")
        return True

    except Exception as e:
        logging.error("Firebase initialization failed: %s", e)
        return False


def upload_to_firebase(payload: Dict[str, Any], timestamp_key: str) -> bool:
    """Upload payload to Firebase RTDB."""
    try:
        path = f"stations/{DEVICE_ID}/{timestamp_key}"
        db.reference(path).set(payload)
        logging.info("Uploaded successfully to %s", path)
        return True
    except Exception as e:
        logging.error("Firebase upload failed: %s", e)
        return False


# ============================================================
# SERIAL / USB DETECTION
# ============================================================

def list_available_ports() -> None:
    """Log all detected serial ports."""
    ports = list(serial.tools.list_ports.comports())

    if not ports:
        logging.warning("No serial ports detected.")
        return

    logging.info("Available serial ports:")
    for p in ports:
        logging.info(
            "  device=%s | desc=%s | hwid=%s | location=%s",
            p.device,
            p.description,
            p.hwid,
            getattr(p, "location", None)
        )


def port_exists(device_path: Optional[str]) -> bool:
    """Check whether a given serial port exists."""
    if not device_path:
        return False
    return any(p.device == device_path for p in serial.tools.list_ports.comports())


def find_port_by_keywords(keywords: Tuple[str, ...], used_ports: set) -> Optional[str]:
    """
    Find a serial port by matching keywords against:
    - device
    - description
    - hwid
    - location
    """
    if not keywords:
        return None

    ports = list(serial.tools.list_ports.comports())

    for p in ports:
        if p.device in used_ports:
            continue

        haystack = " | ".join([
            str(p.device or ""),
            str(p.description or ""),
            str(p.hwid or ""),
            str(getattr(p, "location", "") or ""),
        ])

        for kw in keywords:
            if kw and kw in haystack:
                return p.device

    return None


def resolve_sensor_ports() -> Dict[str, Optional[str]]:
    """
    Resolve ports for all sensors.
    Priority:
    1. Match Linux USB LOCATION keywords
    2. Manual fallback port
    """
    resolved: Dict[str, Optional[str]] = {}
    used_ports = set()

    for sensor_name, cfg in SENSOR_CONFIGS.items():
        selected_port = None

        selected_port = find_port_by_keywords(cfg.location_keywords, used_ports)

        if not selected_port and port_exists(cfg.manual_port):
            selected_port = cfg.manual_port

        resolved[sensor_name] = selected_port

        if selected_port:
            used_ports.add(selected_port)
            logging.info("%s assigned to %s", sensor_name, selected_port)
        else:
            logging.warning("%s port not resolved.", sensor_name)

    return resolved


# ============================================================
# MODBUS HELPERS
# ============================================================

def create_instrument(port: Optional[str], baudrate: int) -> Optional[minimalmodbus.Instrument]:
    """Create and configure a Modbus RTU instrument."""
    if not port:
        return None

    try:
        inst = minimalmodbus.Instrument(port, SLAVE_ID)
        inst.serial.baudrate = baudrate
        inst.serial.bytesize = 8
        inst.serial.parity = serial.PARITY_NONE
        inst.serial.stopbits = 1
        inst.serial.timeout = SERIAL_TIMEOUT
        inst.mode = minimalmodbus.MODE_RTU

        # Stable behavior on Raspberry Pi with multiple USB converters
        inst.clear_buffers_before_each_transaction = True
        inst.close_port_after_each_call = True

        logging.info("Instrument created: port=%s baud=%s", port, baudrate)
        return inst

    except Exception as e:
        logging.error("Failed to create instrument on %s: %s", port, e)
        return None


def safe_read_register(
    inst: Optional[minimalmodbus.Instrument],
    register_address: int,
    decimals: int = 0,
    function_code: int = 3,
    sensor_name: str = "unknown"
) -> Optional[float]:
    """Safely read one register."""
    if inst is None:
        return None

    try:
        return inst.read_register(register_address, decimals, functioncode=function_code)

    except minimalmodbus.NoResponseError:
        logging.warning("%s: no response.", sensor_name)
    except minimalmodbus.IllegalRequestError:
        logging.warning("%s: illegal request at reg=%s fc=%s", sensor_name, register_address, function_code)
    except Exception as e:
        logging.warning("%s: read_register error: %s", sensor_name, e)

    return None


def safe_read_register_fallback_fc(
    inst: Optional[minimalmodbus.Instrument],
    register_address: int,
    decimals: int = 0,
    primary_fc: int = 3,
    fallback_fc: int = 4,
    sensor_name: str = "unknown"
) -> Optional[float]:
    """Try reading with primary function code first, then fallback."""
    if inst is None:
        return None

    value = safe_read_register(inst, register_address, decimals, primary_fc, sensor_name)
    if value is not None:
        return value

    logging.info("%s: trying fallback function code %s", sensor_name, fallback_fc)
    return safe_read_register(inst, register_address, decimals, fallback_fc, sensor_name)


def safe_read_registers(
    inst: Optional[minimalmodbus.Instrument],
    register_address: int,
    count: int,
    function_code: int = 3,
    sensor_name: str = "unknown"
) -> Optional[list]:
    """Safely read multiple registers."""
    if inst is None:
        return None

    try:
        return inst.read_registers(register_address, count, functioncode=function_code)

    except minimalmodbus.NoResponseError:
        logging.warning("%s: no response while reading %s registers.", sensor_name, count)
    except minimalmodbus.IllegalRequestError:
        logging.warning("%s: illegal request for %s registers.", sensor_name, count)
    except Exception as e:
        logging.warning("%s: read_registers error: %s", sensor_name, e)

    return None


# ============================================================
# SENSOR READERS
# ============================================================

def read_wind_speed(inst: Optional[minimalmodbus.Instrument]) -> Optional[float]:
    return safe_read_register(
        inst=inst,
        register_address=0,
        decimals=1,
        function_code=3,
        sensor_name="wind_speed"
    )


def read_wind_direction(inst: Optional[minimalmodbus.Instrument]) -> Tuple[Optional[float], Optional[str]]:
    gear = safe_read_register(
        inst=inst,
        register_address=0,
        decimals=0,
        function_code=3,
        sensor_name="wind_dir"
    )

    if gear is None:
        return None, None

    try:
        gear_int = int(max(0, min(15, int(gear))))
        degree = gear_int * 22.5
        direction = UNIVERSAL_DIRS[gear_int]
        return degree, direction
    except Exception as e:
        logging.warning("wind_dir: conversion error: %s", e)
        return None, None


def read_soil(inst: Optional[minimalmodbus.Instrument]) -> Dict[str, Optional[float]]:
    regs = safe_read_registers(
        inst=inst,
        register_address=0,
        count=7,
        function_code=3,
        sensor_name="soil"
    )

    if not regs or len(regs) != 7:
        return {
            "moist": None,
            "temp": None,
            "ec": None,
            "n": None,
            "p": None,
            "k": None,
            "ph": None,
        }

    try:
        return {
            "moist": round(regs[0] * 0.1, 1),
            "temp": round(regs[1] * 0.1, 1),
            "ec": regs[2],
            "n": regs[3],
            "p": regs[4],
            "k": regs[5],
            "ph": round(regs[6] * 0.1, 1),
        }
    except Exception as e:
        logging.warning("soil: parsing error: %s", e)
        return {
            "moist": None,
            "temp": None,
            "ec": None,
            "n": None,
            "p": None,
            "k": None,
            "ph": None,
        }


def read_rain(inst: Optional[minimalmodbus.Instrument]) -> Optional[float]:
    value = safe_read_register(
        inst=inst,
        register_address=0,
        decimals=0,
        function_code=3,
        sensor_name="rain"
    )

    if value is None:
        return None

    try:
        return round(float(value) / 10.0, 1)
    except Exception as e:
        logging.warning("rain: conversion error: %s", e)
        return None


def read_solar_radiation(inst: Optional[minimalmodbus.Instrument]) -> Optional[float]:
    value = safe_read_register_fallback_fc(
        inst=inst,
        register_address=0,
        decimals=0,
        primary_fc=3,
        fallback_fc=4,
        sensor_name="solar"
    )

    if value is None:
        return None

    try:
        return float(value)
    except Exception as e:
        logging.warning("solar: conversion error: %s", e)
        return None


# ============================================================
# PAYLOAD / STATUS
# ============================================================

def build_payload(instruments: Dict[str, Optional[minimalmodbus.Instrument]]) -> Dict[str, Any]:
    """Read all sensors and build payload."""

    wind_speed = read_wind_speed(instruments.get("wind_speed"))
    wind_deg, wind_dir = read_wind_direction(instruments.get("wind_dir"))
    soil_data = read_soil(instruments.get("soil"))
    rainfall = read_rain(instruments.get("rain"))
    solar = read_solar_radiation(instruments.get("solar"))

    payload = {
        "ws": wind_speed,
        "wd_deg": wind_deg,
        "wd_dir": wind_dir,
        "moist": soil_data["moist"],
        "temp": soil_data["temp"],
        "ec": soil_data["ec"],
        "n": soil_data["n"],
        "p": soil_data["p"],
        "k": soil_data["k"],
        "ph": soil_data["ph"],
        "rain": rainfall,
        "solar": solar,
    }

    return payload


def get_timestamp_key() -> str:
    """Firebase-safe UTC timestamp key."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sensor_status(value: Any) -> str:
    return "ONLINE" if value is not None else "OFFLINE"


def styled_status(value: Any) -> str:
    if value is None:
        return color_text("OFFLINE", C.RED, bold=True)
    return color_text("ONLINE", C.GREEN, bold=True)


def format_value(value: Any, unit: str = "") -> str:
    if value is None:
        return color_text("N/A", C.YELLOW, bold=True)
    if unit:
        return f"{value} {unit}"
    return str(value)


def overall_system_status(payload: Dict[str, Any]) -> str:
    values = list(payload.values())
    active_count = sum(1 for v in values if v is not None)
    total_count = len(values)

    if active_count == total_count:
        return color_text("FULLY OPERATIONAL", C.GREEN, bold=True)
    if active_count > 0:
        return color_text("PARTIALLY OPERATIONAL", C.YELLOW, bold=True)
    return color_text("NO SENSOR DATA", C.RED, bold=True)


def print_line(label: str, value: str, status: str, color: str = C.CYAN) -> None:
    print(f"{color_text(label.ljust(22), color, bold=True)} : {value} | Status: {status}  {color_text(STYLE_SUFFIX, C.MAGENTA, bold=True)}")


def print_startup_banner() -> None:
    print("\n" + "=" * 86)
    print(color_text("SMART WEATHER STATION INITIALIZED", C.BLUE, bold=True))
    print(color_text(f"Device ID           : {DEVICE_ID}", C.WHITE, bold=True))
    print(color_text(f"Polling Interval    : {POLL_INTERVAL_SECONDS} second(s)", C.WHITE, bold=True))
    print(color_text(f"Database URL        : {DATABASE_URL}", C.WHITE, bold=True))
    print("=" * 86 + "\n")


def print_port_mapping(resolved_ports: Dict[str, Optional[str]]) -> None:
    print(color_text("SENSOR PORT MAPPING", C.BLUE, bold=True))
    print("-" * 86)
    for sensor_name, port in resolved_ports.items():
        status = styled_status(port)
        value = port if port else color_text("NOT RESOLVED", C.RED, bold=True)
        print_line(sensor_name.replace("_", " ").title(), str(value), status, C.CYAN)
    print("-" * 86 + "\n")


def print_dashboard(
    timestamp_key: str,
    payload: Dict[str, Any],
    resolved_ports: Dict[str, Optional[str]],
    upload_status: Optional[bool] = None
) -> None:
    print("\n" + "=" * 86)
    print(color_text("LIVE WEATHER STATION DASHBOARD", C.BLUE, bold=True))
    print("=" * 86)

    print_line("Timestamp UTC", timestamp_key, color_text("ACTIVE", C.GREEN, bold=True), C.WHITE)
    print_line("Device ID", DEVICE_ID, color_text("ACTIVE", C.GREEN, bold=True), C.WHITE)
    print_line("System Status", overall_system_status(payload), color_text("MONITORING", C.GREEN, bold=True), C.WHITE)

    if upload_status is None:
        upload_display = color_text("PENDING", C.YELLOW, bold=True)
    elif upload_status:
        upload_display = color_text("SUCCESS", C.GREEN, bold=True)
    else:
        upload_display = color_text("FAILED", C.RED, bold=True)

    print_line("Firebase Upload", upload_display, color_text("SYNC", C.GREEN, bold=True), C.WHITE)

    print("-" * 86)
    print(color_text("SENSOR READINGS", C.BLUE, bold=True))
    print("-" * 86)

    print_line("Wind Speed", format_value(payload["ws"], "m/s"), styled_status(payload["ws"]))
    wind_dir_val = "N/A" if payload["wd_deg"] is None else f'{payload["wd_deg"]}° ({payload["wd_dir"]})'
    print_line("Wind Direction", wind_dir_val, styled_status(payload["wd_deg"]))
    print_line("Soil Moisture", format_value(payload["moist"], "%"), styled_status(payload["moist"]))
    print_line("Soil Temperature", format_value(payload["temp"], "°C"), styled_status(payload["temp"]))
    print_line("Soil EC", format_value(payload["ec"], "uS/cm"), styled_status(payload["ec"]))
    print_line("Soil Nitrogen", format_value(payload["n"], "mg/kg"), styled_status(payload["n"]))
    print_line("Soil Phosphorus", format_value(payload["p"], "mg/kg"), styled_status(payload["p"]))
    print_line("Soil Potassium", format_value(payload["k"], "mg/kg"), styled_status(payload["k"]))
    print_line("Soil pH", format_value(payload["ph"]), styled_status(payload["ph"]))
    print_line("Rainfall", format_value(payload["rain"], "mm"), styled_status(payload["rain"]))
    print_line("Solar Radiation", format_value(payload["solar"], "W/m²"), styled_status(payload["solar"]))

    print("-" * 86)
    print(color_text("PORT STATUS", C.BLUE, bold=True))
    print("-" * 86)

    for sensor_name, port in resolved_ports.items():
        label = f"{sensor_name.replace('_', ' ').title()} Port"
        port_val = port if port else "NOT RESOLVED"
        stat = styled_status(port)
        print_line(label, port_val, stat, C.YELLOW)

    print("=" * 86)
    print()


# ============================================================
# MAIN
# ============================================================

def main() -> None:
    logging.info("Starting integrated weather station script...")

    print_startup_banner()

    wifi_ok = connect_wifi()
    firebase_ok = init_firebase()

    list_available_ports()
    resolved_ports = resolve_sensor_ports()

    print_port_mapping(resolved_ports)

    instruments = {
        name: create_instrument(port, SENSOR_CONFIGS[name].baudrate)
        for name, port in resolved_ports.items()
    }

    logging.info("Polling every %s second(s).", POLL_INTERVAL_SECONDS)

    cycle_count = 0

    while True:
        cycle_start = time.time()
        cycle_count += 1

        try:
            timestamp_key = get_timestamp_key()
            payload = build_payload(instruments)

            upload_status = None
            if firebase_ok:
                upload_status = upload_to_firebase(payload, timestamp_key)
            else:
                upload_status = False
                logging.warning("Skipping Firebase upload because initialization failed.")

            print_dashboard(
                timestamp_key=timestamp_key,
                payload=payload,
                resolved_ports=resolved_ports,
                upload_status=upload_status
            )

            logging.info(
                "Cycle %s complete | Wi-Fi=%s | Firebase=%s",
                cycle_count,
                "OK" if wifi_ok else "CHECK",
                "OK" if firebase_ok else "FAILED"
            )

        except KeyboardInterrupt:
            logging.info("Interrupted by user. Exiting...")
            break

        except Exception as e:
            logging.error("Main loop error: %s", e)

        elapsed = time.time() - cycle_start
        sleep_time = max(0, POLL_INTERVAL_SECONDS - elapsed)
        time.sleep(sleep_time)


if __name__ == "__main__":
    main()
