"""Diagnose and pin RS-485 adapters.

Run these on the Pi, with the backend stopped so the ports are free::

    sudo systemctl stop cropconnect      # or whatever runs uvicorn

    python -m app.tools.ports list       # what adapters exist, and can we anchor them?
    python -m app.tools.ports probe      # what does each adapter actually answer?
    python -m app.tools.ports capture --sensor rain --device /dev/ttyUSB1
    python -m app.tools.ports doctor     # end-to-end verdict
    python -m app.tools.ports udev       # emit udev rules for stable names

Start with ``list``: it tells you whether your CH340 adapters report unique
serial numbers. If they do, everything else is easy. If they do not, use
``probe`` to find out which sensors are distinguishable by fingerprint, then
``capture`` each one, and anchor whatever is left with ``udev``.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from app.config import get_settings
from app.serial_ports import (
    SENSOR_BAUD,
    SENSOR_NAMES,
    Adapter,
    PortResolver,
    SignatureStore,
    enumerate_adapters,
    is_probe_candidate,
    probe_all_bauds,
    probe_device,
    resolve_alias,
    sensor_adapters,
    udev_rules,
)


def _excluded_devices() -> list[str]:
    """Devices that are not RS-485 sensor adapters and must not be probed."""
    gps_port = get_settings().gps_port
    return [gps_port] if gps_port else []


def _make_resolver() -> PortResolver:
    settings = get_settings()
    return PortResolver(
        _pins(),
        SignatureStore.load(_signature_path()),
        strict=settings.sensor_strict_identity,
        probe_enabled=settings.sensor_fingerprint_enabled,
        exclude_devices=_excluded_devices(),
    )


def _signature_path() -> Path:
    return Path(get_settings().sensor_signature_file)


def _pins() -> dict[str, str | None]:
    settings = get_settings()
    return {
        "wind_speed": settings.wind_speed_port,
        "wind_direction": settings.wind_direction_port,
        "soil": settings.soil_port,
        "rain": settings.rain_port,
        "solar": settings.solar_port,
    }


def _print_table(rows: list[list[str]], headers: list[str]) -> None:
    widths = [len(h) for h in headers]
    for row in rows:
        for index, cell in enumerate(row):
            widths[index] = max(widths[index], len(cell))
    line = "  ".join(h.ljust(widths[i]) for i, h in enumerate(headers))
    print(line)
    print("  ".join("-" * widths[i] for i in range(len(headers))))
    for row in rows:
        print("  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)))


# ────────────────────────────────────────────────────────────────────── list ──


def cmd_list(_: argparse.Namespace) -> int:
    adapters = enumerate_adapters()
    if not adapters:
        print("No USB serial adapters found.")
        print("Check the powered hub, then: lsusb && dmesg | tail -30")
        return 1

    excluded = _excluded_devices()
    gps_resolved = {resolve_alias(entry) for entry in excluded}

    rows = []
    for adapter in adapters:
        if adapter.device in gps_resolved or adapter.device in excluded:
            use = "GPS (skip)"
        elif is_probe_candidate(adapter.device, excluded):
            use = "sensor"
        else:
            use = "not a sensor"
        rows.append(
            [
                adapter.device,
                use,
                adapter.serial_number or "-",
                "yes" if adapter.has_usable_serial else "NO",
                adapter.location or "-",
                (adapter.description or "-")[:24],
            ]
        )
    _print_table(
        rows,
        ["device", "use", "usb serial", "anchorable", "usb path", "description"],
    )

    # Only the sensor candidates matter for the anchorable verdict; the Pi's
    # own UARTs and the GPS are never sensor adapters.
    candidates = sensor_adapters(excluded)
    print()
    print(f"{len(candidates)} of {len(adapters)} serial devices are sensor candidates.")
    skipped = [a.device for a in adapters if a not in candidates]
    if skipped:
        print(f"Ignoring (not RS-485 sensors): {', '.join(skipped)}")
    print()

    if not candidates:
        print("No sensor adapters found. Check the powered hub.")
        return 1

    anchorable = [a for a in candidates if a.has_usable_serial]
    if len(anchorable) == len(candidates):
        print(f"GOOD: all {len(candidates)} sensor adapters report a usable serial number.")
        print("Anchor everything by serial — go to README Step 4A.")
    elif anchorable:
        print(
            f"PARTIAL: {len(anchorable)} of {len(candidates)} sensor adapters have a usable serial."
        )
        print("Go to README Step 4B — it covers both anchored and unanchored adapters.")
    else:
        print("NONE of the sensor adapters report a usable serial number.")
        print("This is normal for CH340 clones and is why /dev/serial/by-id did not work.")
        print("Next: python -m app.tools.ports probe   (README Step 4B.1)")

    print()
    print("Configured pins:")
    for sensor, pin in _pins().items():
        resolved = resolve_alias(pin)
        state = "present" if resolved else ("MISSING" if pin else "not set")
        print(f"  {sensor:<16} {pin or '-'}")
        print(f"  {'':<16}   -> {resolved or state}")
    return 0


# ───────────────────────────────────────────────────────────────────── probe ──


def cmd_probe(args: argparse.Namespace) -> int:
    excluded = _excluded_devices()
    if args.device:
        # An explicit --device is honoured, but still guarded: probing the GPS
        # or a built-in UART is never useful.
        if not is_probe_candidate(args.device, excluded):
            print(f"Refusing to probe {args.device}: not an RS-485 sensor adapter.")
            print("Sensor adapters are /dev/ttyUSB* (or /dev/ttyACM* other than the GPS).")
            return 2
        devices = [args.device]
    else:
        devices = [adapter.device for adapter in sensor_adapters(excluded)]

    if not devices:
        print("No sensor adapters to probe.")
        return 1

    print(f"Probing {len(devices)} sensor adapter(s) at 4800 then 9600.")
    print("This takes a few seconds per port.")
    print()
    rows = []
    signatures: dict[str, list[str]] = {}
    for device in devices:
        results = probe_all_bauds(device)
        hit = next((r for r in results if r.responded and r.fingerprint), None)
        if hit is None or hit.fingerprint is None:
            rows.append([device, "-", "-", "-", "no response at 4800 or 9600"])
            continue
        fp = hit.fingerprint
        signatures.setdefault(fp.key, []).append(device)
        rows.append(
            [
                device,
                str(fp.baud),
                str(fp.blocks),
                "yes" if fp.fc4 else "no",
                f"{fp.key}   reg0={hit.register0}",
            ]
        )
    _print_table(rows, ["device", "baud", "regs", "fc4", "signature / value"])

    print()
    collisions = {key: devs for key, devs in signatures.items() if len(devs) > 1}
    if collisions:
        print("Devices sharing a signature (NOT distinguishable by probing):")
        for key, devs in collisions.items():
            print(f"  {key}: {', '.join(devs)}")
        print()
        print("These must be anchored by USB serial or hub socket — see `udev`.")
    else:
        print("Every responding adapter has a unique signature.")
        print("Capture them so the station can self-identify regardless of port names:")
        print("  python -m app.tools.ports capture --sensor <name> --device <device>")
    return 0


# ─────────────────────────────────────────────────────────────────── capture ──


def cmd_capture(args: argparse.Namespace) -> int:
    sensor: str = args.sensor
    if sensor not in SENSOR_NAMES:
        print(f"Unknown sensor '{sensor}'. Expected one of: {', '.join(SENSOR_NAMES)}")
        return 2

    excluded = _excluded_devices()
    device = args.device
    if device is None:
        adapters = sensor_adapters(excluded)
        if len(adapters) != 1:
            print(
                "Pass --device, or connect only the one sensor you are capturing "
                f"(found {len(adapters)} sensor adapters)."
            )
            if adapters:
                print("Present: " + ", ".join(a.device for a in adapters))
            return 2
        device = adapters[0].device
    elif not is_probe_candidate(device, excluded):
        print(f"Refusing to probe {device}: not an RS-485 sensor adapter.")
        return 2

    baud = args.baud or SENSOR_BAUD[sensor]
    print(f"Probing {sensor} on {device} at {baud} baud…")
    result = probe_device(device, baud)
    if not result.responded or result.fingerprint is None:
        print(f"FAILED: no response ({result.error}).")
        print("Check power, A/B polarity and that this really is the right sensor.")
        return 1

    store = SignatureStore.load(_signature_path())
    store.record(sensor, result.fingerprint)
    store.save()

    print(f"Captured {sensor}: signature {result.fingerprint.key} (reg0={result.register0})")
    print(f"Saved to {store.path}")

    conflicts = store.conflicts()
    if conflicts:
        print()
        print("WARNING — these signatures are claimed by more than one sensor:")
        for key, sensors in conflicts.items():
            print(f"  {key}: {', '.join(sensors)}")
        print("Those sensors cannot be identified by probing; anchor them with `udev`.")
    return 0


# ──────────────────────────────────────────────────────────────────── doctor ──


def cmd_doctor(_: argparse.Namespace) -> int:
    resolver = _make_resolver()
    resolver.resolve()

    rows = []
    for sensor in SENSOR_NAMES:
        assignment = resolver.assignments.get(sensor)
        if assignment is None:
            rows.append([sensor, "-", "-", "-", "not evaluated"])
            continue
        readable = resolver.device_for(sensor)
        rows.append(
            [
                sensor,
                assignment.device or "-",
                assignment.method,
                assignment.confidence,
                "will read" if readable else f"WILL PUBLISH NULL — {assignment.detail}",
            ]
        )
    _print_table(rows, ["sensor", "device", "method", "confidence", "verdict"])

    print()
    if resolver.notes:
        print("Notes:")
        for note in resolver.notes:
            print(f"  - {note}")
        print()

    blocked = [s for s in SENSOR_NAMES if resolver.device_for(s) is None]
    if not blocked:
        print("All five sensors are positively identified.")
        return 0

    print(f"{len(blocked)} sensor(s) will publish null: {', '.join(blocked)}")
    print()
    print("Fix in this order:")
    print("  1. python -m app.tools.ports list    — do the adapters have serials?")
    print("  2. python -m app.tools.ports probe   — which sensors are distinguishable?")
    print("  3. python -m app.tools.ports capture --sensor X   — teach the station each one")
    print("  4. python -m app.tools.ports udev    — pin whatever is left to a hub socket")
    return 1


# ────────────────────────────────────────────────────────────────────── udev ──


def cmd_udev(args: argparse.Namespace) -> int:
    adapters = sensor_adapters(_excluded_devices())
    if not adapters:
        print("No sensor adapters present; plug them in first.")
        return 1

    mapping: dict[str, Adapter] = {}
    pins = _pins()
    for sensor in SENSOR_NAMES:
        device = resolve_alias(pins.get(sensor))
        if device is None:
            continue
        for adapter in adapters:
            if adapter.device == device:
                mapping[sensor] = adapter
                break

    missing = [s for s in SENSOR_NAMES if s not in mapping]
    if missing:
        print(
            "# NOTE: no current pin resolves for: " + ", ".join(missing),
            file=sys.stderr,
        )
        print(
            "# Set those *_PORT values to the correct device first, then re-run.",
            file=sys.stderr,
        )

    text = udev_rules(mapping)
    if args.output:
        Path(args.output).write_text(text + "\n", encoding="utf-8")
        print(f"Wrote {args.output}")
        print("Install with:")
        print(f"  sudo cp {args.output} /etc/udev/rules.d/99-cropconnect-rs485.rules")
        print("  sudo udevadm control --reload-rules && sudo udevadm trigger")
        print()
        print("Then point .env at the stable names:")
        for sensor in SENSOR_NAMES:
            print(f"  {sensor.upper()}_PORT=/dev/rs485-{sensor.replace('_', '-')}")
    else:
        print(text)
    return 0


# ──────────────────────────────────────────────────────────────────── status ──


def cmd_status(_: argparse.Namespace) -> int:
    resolver = _make_resolver()
    resolver.resolve()
    print(json.dumps(resolver.status(), indent=2, default=str))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m app.tools.ports",
        description="Diagnose and pin the station's RS-485 USB adapters.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="list adapters and whether they can be anchored").set_defaults(
        func=cmd_list
    )

    probe = sub.add_parser("probe", help="probe adapters and show their fingerprints")
    probe.add_argument("--device", help="probe only this device")
    probe.set_defaults(func=cmd_probe)

    capture = sub.add_parser("capture", help="record a sensor's fingerprint")
    capture.add_argument("--sensor", required=True, choices=list(SENSOR_NAMES))
    capture.add_argument("--device", help="device to probe (default: the only adapter present)")
    capture.add_argument("--baud", type=int, help="override the expected baud rate")
    capture.set_defaults(func=cmd_capture)

    sub.add_parser("doctor", help="end-to-end identity verdict").set_defaults(func=cmd_doctor)
    sub.add_parser("status", help="machine-readable resolver status").set_defaults(func=cmd_status)

    udev = sub.add_parser("udev", help="generate udev rules for stable device names")
    udev.add_argument("--output", "-o", help="write to this file instead of stdout")
    udev.set_defaults(func=cmd_udev)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
