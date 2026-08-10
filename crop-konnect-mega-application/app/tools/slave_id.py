"""Discover and change Modbus slave IDs on the RS-485 sensors.

Why
---
All five sensors ship with slave id 1, which is the root cause of every port
identity problem in this project: four of them are protocol-identical, so no
software can tell them apart. If each sensor can be given a unique id, all the
4800-baud ones can share ONE bus and ONE USB adapter, identity lives inside the
sensor, and Linux device naming stops mattering forever.

Most of these OEM sensors *do* expose a writable address register even when the
datasheet calls the default "fixed". This tool finds out.

Order of operations
-------------------
    # 1. Read-only. Safe. Run this first on every sensor.
    python -m app.tools.slave_id scan --sensor rain

    # 2. Still read-only, but slower: sweep for the config register.
    python -m app.tools.slave_id sweep --sensor rain

    # 3. Reversible write test: change the id, verify, change it back.
    python -m app.tools.slave_id test --sensor rain --register 0x07D0 --new-id 4

    # 4. Make it permanent once the test passes.
    python -m app.tools.slave_id set --sensor rain --register 0x07D0 --new-id 4

Safety
------
``scan`` and ``sweep`` never write. ``test`` and ``set`` write and require
``--yes``. Writing an unknown register can disturb calibration, so both refuse
to run unless you name the register explicitly — there is no "try everything"
mode on purpose.

Run with the backend stopped, and with only the sensor you are working on
powered if you can, so a mistake cannot reach a different device.
"""

from __future__ import annotations

import argparse
import time

import minimalmodbus
import serial

from app.config import get_settings
from app.serial_ports import (
    SENSOR_BAUD,
    SENSOR_NAMES,
    is_probe_candidate,
    resolve_alias,
)


# Registers that OEM RS-485 sensors of this class commonly use for the device
# address and baud rate. These are *candidates gathered from the family*, not a
# guarantee for your specific models — that is exactly what `scan` verifies.
CANDIDATE_ADDRESS_REGISTERS: list[tuple[int, str]] = [
    (0x07D0, "CWT family device address (most common)"),
    (0x07D1, "CWT family baud rate (usually address+1)"),
    (0x0100, "alt. address block"),
    (0x0101, "alt. baud (address+1)"),
    (0x0200, "alt. address block"),
    (0x0FA0, "alt. address block"),
    (0x1000, "alt. address block"),
    (0x2000, "alt. address block"),
    (0x0064, "low config block"),
    (0x00FA, "low config block"),
    (0x0007, "just past the 7-register data block"),
    (0x0008, "just past the 7-register data block"),
]

# Baud codes seen on these sensors. Used only to *guess* whether a register
# looks like a baud setting, never to write.
BAUD_CODE_HINTS = {
    0: "2400?",
    1: "4800?",
    2: "9600?",
    3: "19200?",
    4: "38400?",
    24: "2400?",
    48: "4800?",
    96: "9600?",
}

READ_TIMEOUT = 0.35


# ─────────────────────────────────────────────────────────────────── helpers ──


def _pins() -> dict[str, str | None]:
    settings = get_settings()
    return {
        "wind_speed": settings.wind_speed_port,
        "wind_direction": settings.wind_direction_port,
        "soil": settings.soil_port,
        "rain": settings.rain_port,
        "solar": settings.solar_port,
    }


def _resolve_target(args: argparse.Namespace) -> tuple[str, int, str] | None:
    """Return (device, baud, label) for the requested sensor/device."""
    if args.device:
        device = args.device
        baud = args.baud or 4800
        label = f"{device} @{baud}"
        if not is_probe_candidate(device, []):
            print(f"Refusing to touch {device}: not an RS-485 sensor adapter.")
            return None
        return device, baud, label

    sensor = args.sensor
    if sensor not in SENSOR_NAMES:
        print(f"Unknown sensor '{sensor}'. Expected one of: {', '.join(SENSOR_NAMES)}")
        return None

    pin = _pins().get(sensor)
    device = resolve_alias(pin)
    if device is None:
        print(f"{sensor}: configured port is not present ({pin or 'not set'}).")
        print("Fix the *_PORT value in .env, or pass --device explicitly.")
        return None

    baud = args.baud or SENSOR_BAUD[sensor]
    return device, baud, f"{sensor} on {device} @{baud}"


def _instrument(device: str, baud: int, slave_id: int) -> minimalmodbus.Instrument:
    instrument = minimalmodbus.Instrument(device, slave_id)
    instrument.serial.baudrate = baud
    instrument.serial.bytesize = 8
    instrument.serial.parity = serial.PARITY_NONE
    instrument.serial.stopbits = 1
    instrument.serial.timeout = READ_TIMEOUT
    instrument.mode = minimalmodbus.MODE_RTU
    instrument.clear_buffers_before_each_transaction = True
    instrument.close_port_after_each_call = True
    return instrument


def _read(device: str, baud: int, slave_id: int, register: int) -> int | None:
    """Read one holding register. Returns None on any failure."""
    try:
        instrument = _instrument(device, baud, slave_id)
    except Exception:
        return None
    try:
        return int(instrument.read_register(register, 0, functioncode=3))
    except Exception:
        return None
    finally:
        try:
            if instrument.serial and instrument.serial.is_open:
                instrument.serial.close()
        except Exception:
            pass


def _write(device: str, baud: int, slave_id: int, register: int, value: int) -> str | None:
    """Write one holding register. Returns None on success, else the error."""
    try:
        instrument = _instrument(device, baud, slave_id)
    except Exception as exc:
        return f"open failed: {exc}"
    try:
        instrument.write_register(register, value, 0, functioncode=6)
        return None
    except Exception as exc:
        return str(exc)
    finally:
        try:
            if instrument.serial and instrument.serial.is_open:
                instrument.serial.close()
        except Exception:
            pass


def _responds(device: str, baud: int, slave_id: int) -> bool:
    return _read(device, baud, slave_id, 0) is not None


def _print_table(rows: list[list[str]], headers: list[str]) -> None:
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))
    print("  ".join(h.ljust(widths[i]) for i, h in enumerate(headers)))
    print("  ".join("-" * widths[i] for i in range(len(headers))))
    for row in rows:
        print("  ".join(cell.ljust(widths[i]) for i, cell in enumerate(row)))


# ────────────────────────────────────────────────────────────────────── scan ──


def cmd_scan(args: argparse.Namespace) -> int:
    target = _resolve_target(args)
    if target is None:
        return 2
    device, baud, label = target

    print(f"Scanning {label} — READ ONLY, nothing is written.")
    print()

    # ── Which slave ids answer at all? ────────────────────────────────────
    ids = list(range(1, 17)) + [247]
    if args.full:
        ids = list(range(1, 248))
    print(f"Looking for responding slave ids ({len(ids)} to try)…")
    found = [sid for sid in ids if _responds(device, baud, sid)]
    if not found:
        print("No slave id responded. Check power, A/B polarity and baud rate.")
        print(f"(tried baud {baud}; pass --baud to change)")
        return 1
    print(f"Responding slave id(s): {', '.join(str(s) for s in found)}")
    current = found[0]
    if len(found) > 1:
        print("NOTE: more than one id answered — this device may ignore the id")
        print("      field entirely, which would make re-addressing useless here.")
    print()

    # ── Do the candidate config registers read back? ──────────────────────
    print(f"Reading candidate config registers at slave id {current}:")
    rows = []
    hits: list[tuple[int, int]] = []
    for register, note in CANDIDATE_ADDRESS_REGISTERS:
        value = _read(device, baud, current, register)
        if value is None:
            rows.append([f"0x{register:04X}", str(register), "-", "no response", note])
            continue
        hits.append((register, value))
        flag = ""
        if value == current:
            flag = "<== LOOKS LIKE THE ADDRESS REGISTER"
        elif value in BAUD_CODE_HINTS:
            flag = f"maybe baud ({BAUD_CODE_HINTS[value]})"
        rows.append([f"0x{register:04X}", str(register), str(value), flag, note])
    _print_table(rows, ["reg (hex)", "dec", "value", "interpretation", "note"])
    print()

    # ── Verdict ───────────────────────────────────────────────────────────
    address_candidates = [reg for reg, value in hits if value == current]

    if len(hits) == len(CANDIDATE_ADDRESS_REGISTERS):
        print("WARNING: every candidate register responded, including ones that")
        print("should not exist. This firmware does not validate register")
        print("addresses, so a read scan cannot locate the config register —")
        print("the values above are not trustworthy.")
        print()
        print("Next: check the datasheet for this model, then verify with")
        print("      `test --register <addr>` which is reversible.")
        return 0

    if address_candidates:
        best = address_candidates[0]
        print("LIKELY RE-ADDRESSABLE.")
        print(f"Register 0x{best:04X} reads back {current}, matching the current slave id.")
        print()
        print("Verify it reversibly (writes, then restores):")
        print(
            f"  python -m app.tools.slave_id test --sensor {args.sensor} "
            f"--register 0x{best:04X} --new-id {args.suggest_id} --yes"
        )
        return 0

    if hits:
        print("INCONCLUSIVE: some registers responded, but none read back the")
        print(f"current slave id ({current}), so none is an obvious address register.")
        print("Check the datasheet, then use `test --register <addr>` to try one.")
        return 0

    print("NOT RE-ADDRESSABLE by these candidates: none of them responded.")
    print("Try `sweep` to search a wider range, or check the datasheet.")
    return 0


# ───────────────────────────────────────────────────────────────────── sweep ──


def cmd_sweep(args: argparse.Namespace) -> int:
    target = _resolve_target(args)
    if target is None:
        return 2
    device, baud, label = target

    start = args.start
    end = args.end
    if end < start:
        print("--end must be >= --start")
        return 2

    slave_id = args.slave_id
    if not _responds(device, baud, slave_id):
        print(f"Slave id {slave_id} does not respond on {label}. Run `scan` first.")
        return 1

    total = end - start + 1
    print(f"Sweeping {label}, registers 0x{start:04X}–0x{end:04X} ({total}) — READ ONLY.")
    print(f"At ~{READ_TIMEOUT}s per miss this can take a while. Ctrl-C to stop.")
    print()

    readable: list[tuple[int, int]] = []
    try:
        for register in range(start, end + 1):
            value = _read(device, baud, slave_id, register)
            if value is not None:
                readable.append((register, value))
                marker = " <== matches current slave id" if value == slave_id else ""
                print(f"  0x{register:04X} ({register:>5}) = {value}{marker}")
    except KeyboardInterrupt:
        print("\nStopped.")

    print()
    if not readable:
        print("No registers responded in that range.")
        return 0

    if len(readable) == total:
        print(f"All {total} registers responded — this firmware does not validate")
        print("register addresses, so a sweep cannot identify the config register.")
        print("You need the datasheet for this model.")
        return 0

    matches = [reg for reg, value in readable if value == slave_id]
    print(f"{len(readable)} of {total} registers responded.")
    if matches:
        print("Registers reading back the current slave id (best candidates):")
        for reg in matches:
            print(f"  0x{reg:04X} ({reg})")
        print()
        print("Verify one reversibly with `test --register <addr>`.")
    return 0


# ────────────────────────────────────────────────────────────────────── test ──


def cmd_test(args: argparse.Namespace) -> int:
    target = _resolve_target(args)
    if target is None:
        return 2
    device, baud, label = target

    register = args.register
    new_id = args.new_id
    if not 1 <= new_id <= 247:
        print("--new-id must be between 1 and 247.")
        return 2

    old_id = args.slave_id
    if not _responds(device, baud, old_id):
        print(f"Slave id {old_id} does not respond on {label}. Run `scan` first.")
        return 1

    if not args.yes:
        print(f"This WRITES register 0x{register:04X} on {label}.")
        print(f"It will set the slave id to {new_id}, verify, then restore {old_id}.")
        print("Re-run with --yes to proceed.")
        return 2

    before = _read(device, baud, old_id, register)
    print(f"Register 0x{register:04X} currently reads: {before}")
    print(f"Writing {new_id}…")

    error = _write(device, baud, old_id, register, new_id)
    if error is not None:
        print(f"WRITE REJECTED: {error}")
        print()
        print("This register is not writable. Either it is the wrong register, or")
        print("this sensor's address really is fixed. Try another candidate, or")
        print("keep the udev socket-pinning approach.")
        return 1

    print("Write accepted. Waiting for the device to apply it…")
    time.sleep(1.5)

    answers_new = _responds(device, baud, new_id)
    answers_old = _responds(device, baud, old_id)

    print()
    if answers_new and not answers_old:
        print(f"SUCCESS: the device now answers at slave id {new_id} and no longer at {old_id}.")
        print("This sensor IS re-addressable.")
        verdict = 0
    elif answers_new and answers_old:
        print(f"PARTIAL: it answers at BOTH {new_id} and {old_id}.")
        print("The device may ignore the id field, which makes re-addressing useless.")
        verdict = 1
    elif answers_old and not answers_new:
        print(f"NO EFFECT: still only answers at {old_id}.")
        print("The write was accepted but did not change the address. Many of these")
        print("sensors apply the new id only after a POWER CYCLE — power this sensor")
        print("off and on, then run:")
        print(f"  python -m app.tools.slave_id scan --sensor {args.sensor}")
        print("If it then answers at the new id, it worked and just needs a reboot.")
        verdict = 1
    else:
        print("The device stopped answering at either id.")
        print("Power-cycle this sensor, then run `scan` to see where it landed.")
        print(f"If it comes back at {new_id}, the change worked.")
        return 1

    # ── Restore ───────────────────────────────────────────────────────────
    if args.keep:
        print()
        print(f"--keep given: leaving the id at {new_id}.")
        print("Remember to update the backend once all sensors are re-addressed.")
        return verdict

    print()
    print(f"Restoring slave id {old_id}…")
    speak_id = new_id if answers_new else old_id
    error = _write(device, baud, speak_id, register, old_id)
    if error is not None:
        print(f"RESTORE FAILED: {error}")
        print(f"The sensor may still be at id {new_id}. Recover with:")
        print(
            f"  python -m app.tools.slave_id set --sensor {args.sensor} "
            f"--register 0x{register:04X} --new-id {old_id} --slave-id {new_id} --yes"
        )
        return 1

    time.sleep(1.5)
    if _responds(device, baud, old_id):
        print(f"Restored: answering at {old_id} again.")
    else:
        print(f"Restore written, but {old_id} is not answering yet — power-cycle and re-scan.")
    return verdict


# ─────────────────────────────────────────────────────────────────────── set ──


def cmd_set(args: argparse.Namespace) -> int:
    target = _resolve_target(args)
    if target is None:
        return 2
    device, baud, label = target

    register = args.register
    new_id = args.new_id
    old_id = args.slave_id
    if not 1 <= new_id <= 247:
        print("--new-id must be between 1 and 247.")
        return 2

    if not args.yes:
        print(f"This PERMANENTLY sets the slave id to {new_id} on {label}")
        print(f"by writing register 0x{register:04X} (currently talking to id {old_id}).")
        print("Re-run with --yes to proceed.")
        return 2

    if not _responds(device, baud, old_id):
        print(f"Warning: slave id {old_id} is not responding; writing anyway.")

    error = _write(device, baud, old_id, register, new_id)
    if error is not None:
        print(f"WRITE REJECTED: {error}")
        return 1

    print("Write accepted. Waiting…")
    time.sleep(1.5)
    if _responds(device, baud, new_id):
        print(f"Confirmed: the sensor answers at slave id {new_id}.")
    else:
        print(f"Written, but {new_id} is not answering yet.")
        print("Power-cycle this sensor, then verify with:")
        print(f"  python -m app.tools.slave_id scan --sensor {args.sensor}")
    return 0


# ──────────────────────────────────────────────────────────────────── parser ──


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m app.tools.slave_id",
        description="Discover and change Modbus slave IDs on the RS-485 sensors.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p: argparse.ArgumentParser) -> None:
        group = p.add_mutually_exclusive_group(required=True)
        group.add_argument("--sensor", choices=list(SENSOR_NAMES), help="use this sensor's configured port")
        group.add_argument("--device", help="talk to this device directly")
        p.add_argument("--baud", type=int, help="override the baud rate")

    scan = sub.add_parser("scan", help="READ ONLY: find responding ids and candidate config registers")
    common(scan)
    scan.add_argument("--full", action="store_true", help="try all 247 slave ids (slow)")
    scan.add_argument("--suggest-id", type=int, default=4, help="id to suggest in the follow-up command")
    scan.set_defaults(func=cmd_scan)

    sweep = sub.add_parser("sweep", help="READ ONLY: sweep a register range looking for the config register")
    common(sweep)
    sweep.add_argument("--slave-id", type=int, default=1, help="id to talk to (default 1)")
    sweep.add_argument(
        "--start", type=lambda v: int(v, 0), default=0x07C0, help="first register (default 0x07C0)"
    )
    sweep.add_argument(
        "--end", type=lambda v: int(v, 0), default=0x07FF, help="last register (default 0x07FF)"
    )
    sweep.set_defaults(func=cmd_sweep)

    test = sub.add_parser("test", help="WRITES: change the id, verify, then change it back")
    common(test)
    test.add_argument("--register", type=lambda v: int(v, 0), required=True, help="config register, e.g. 0x07D0")
    test.add_argument("--new-id", type=int, required=True, help="id to try")
    test.add_argument("--slave-id", type=int, default=1, help="current id (default 1)")
    test.add_argument("--keep", action="store_true", help="do not restore the old id")
    test.add_argument("--yes", action="store_true", help="confirm the write")
    test.set_defaults(func=cmd_test)

    setter = sub.add_parser("set", help="WRITES: set the slave id permanently")
    common(setter)
    setter.add_argument("--register", type=lambda v: int(v, 0), required=True)
    setter.add_argument("--new-id", type=int, required=True)
    setter.add_argument("--slave-id", type=int, default=1, help="current id (default 1)")
    setter.add_argument("--yes", action="store_true", help="confirm the write")
    setter.set_defaults(func=cmd_set)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    # `--device` mode has no sensor name; keep the attribute present for messages.
    if not hasattr(args, "sensor") or args.sensor is None:
        args.sensor = "<sensor>"
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
