"""RS-485 adapter identity resolution.

The problem this solves
----------------------
Every sensor on this station is a Modbus-RTU device with a burned slave id of 1
that answers on holding register 0. Four of the five (wind speed, wind
direction, rain, solar) additionally share the same baud rate of 4800. They are
therefore *protocol-identical*: no single register read can tell them apart.

Each sensor has its own CH340 USB-serial adapter on a powered hub, and Linux
assigns ``/dev/ttyUSB*`` in enumeration order, which is not stable. If the
wiring between "logical sensor" and "device node" is wrong, the station happily
publishes a UV reading as rainfall. That is worse than publishing nothing.

Three anchors, in order of preference
------------------------------------
1. ``serial`` — the adapter's USB iSerial (``/dev/serial/by-id``). Rock solid,
   survives re-plugging into any socket, but most CH340 clones ship without a
   serial number. Use ``python -m app.tools.ports list`` to find out.
2. ``fingerprint`` — probe the device and match it against a signature captured
   from the known-good sensor. Topology-independent: it keeps working when the
   hub re-enumerates. Only usable for sensors whose signatures actually differ
   (soil always differs — 9600 baud, 7 registers).
3. ``path`` — the USB topology path (``/dev/serial/by-path``). Stable only while
   the hub chain enumerates consistently; on cascaded hubs it can shift.

Whatever the anchor, resolution **fails closed**: a sensor whose device cannot
be positively identified is reported as unresolved, and the caller publishes
null rather than a value that might belong to a different sensor.
"""

from __future__ import annotations

import json
import logging
import os
import time
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any, Iterable

import minimalmodbus
import serial
import serial.tools.list_ports


logger = logging.getLogger(__name__)


SENSOR_NAMES = ("wind_speed", "wind_direction", "soil", "rain", "solar")

# Baud per sensor — matches the standalone per-sensor scripts, which are known
# to work. Do not change without re-testing against the hardware.
SENSOR_BAUD: dict[str, int] = {
    "wind_speed": 4800,
    "wind_direction": 4800,
    "soil": 9600,
    "rain": 4800,
    "solar": 4800,
}

# Register-block sizes tried when fingerprinting, largest first. 7 is the soil
# sensor's block; the others expose far fewer.
_PROBE_BLOCKS = (7, 4, 3, 2, 1)

BY_PATH_DIR = Path("/dev/serial/by-path")
BY_ID_DIR = Path("/dev/serial/by-id")

PROBE_TIMEOUT_SECONDS = 0.6

# Only USB-attached serial devices can be RS-485 sensor adapters.
_ADAPTER_PREFIXES = ("/dev/ttyUSB", "/dev/ttyACM")

# Never probe these. The Pi's own UARTs (ttyAMA*, ttyS*) are not sensor
# adapters, and writing Modbus frames at them is pointless at best. The GPS
# receiver is excluded separately, by device, because it enumerates as ttyACM
# exactly like some RS-485 adapters do.
_NEVER_PROBE_PREFIXES = (
    "/dev/ttyAMA",
    "/dev/ttyS",
    "/dev/ttyprintk",
    "/dev/console",
)


# ─────────────────────────────────────────────────────────── Adapter identity ──


@dataclass(frozen=True)
class Adapter:
    """One USB-serial adapter currently present on the system."""

    device: str  # realpath, e.g. /dev/ttyUSB2
    by_path: str | None = None
    by_id: str | None = None
    location: str | None = None  # pyserial USB location, e.g. 1-1.4.4.3.2:1.0
    vid: int | None = None
    pid: int | None = None
    serial_number: str | None = None
    description: str | None = None

    @property
    def has_usable_serial(self) -> bool:
        """True when the adapter reports a serial number worth anchoring on.

        CH340 clones commonly report nothing, or a constant placeholder shared
        by every unit — neither is usable as an identity.
        """
        value = (self.serial_number or "").strip()
        if len(value) < 4:
            return False
        return value.lower() not in {"0000", "00000000", "none", "n/a", "ch340", "serial"}

    def summary(self) -> dict[str, Any]:
        return asdict(self)


def _symlink_map(directory: Path) -> dict[str, str]:
    """Map realpath -> symlink for every entry in a /dev/serial/* directory."""
    mapping: dict[str, str] = {}
    try:
        if not directory.is_dir():
            return mapping
        for entry in directory.iterdir():
            try:
                mapping[os.path.realpath(entry)] = str(entry)
            except OSError:
                continue
    except OSError as exc:
        logger.debug("Could not list %s: %s", directory, exc)
    return mapping


def enumerate_adapters() -> list[Adapter]:
    """List every serial adapter present, annotated with all stable aliases."""
    by_path = _symlink_map(BY_PATH_DIR)
    by_id = _symlink_map(BY_ID_DIR)

    adapters: list[Adapter] = []
    for port in serial.tools.list_ports.comports():
        try:
            real = os.path.realpath(port.device)
        except OSError:
            real = port.device
        adapters.append(
            Adapter(
                device=real,
                by_path=by_path.get(real),
                by_id=by_id.get(real),
                location=getattr(port, "location", None),
                vid=getattr(port, "vid", None),
                pid=getattr(port, "pid", None),
                serial_number=getattr(port, "serial_number", None),
                description=getattr(port, "description", None),
            )
        )
    adapters.sort(key=lambda item: item.device)
    return adapters


def is_probe_candidate(device: str, exclude: Iterable[str] = ()) -> bool:
    """True when a device may be an RS-485 sensor adapter and is safe to probe.

    Filters out the Pi's built-in UARTs and anything explicitly excluded (the
    GPS receiver), so probing never writes Modbus frames at a device that is
    not a sensor.
    """
    if device.startswith(_NEVER_PROBE_PREFIXES):
        return False
    if not device.startswith(_ADAPTER_PREFIXES):
        return False
    for entry in exclude:
        resolved = resolve_alias(entry)
        if resolved is not None and resolved == device:
            return False
        if entry and entry == device:
            return False
    return True


def sensor_adapters(exclude: Iterable[str] = ()) -> list[Adapter]:
    """Adapters that are plausible RS-485 sensor ports (probe-safe)."""
    excluded = list(exclude)
    return [
        adapter
        for adapter in enumerate_adapters()
        if is_probe_candidate(adapter.device, excluded)
    ]


def resolve_alias(value: str | None) -> str | None:
    """Resolve a configured port (device, by-path or by-id) to a real device.

    Returns None when the alias does not currently exist, which is the correct
    outcome for a sensor that is unplugged — the caller must not fall back to
    "some other port".
    """
    if not value:
        return None
    candidate = value.strip()
    if not candidate:
        return None
    try:
        if not os.path.exists(candidate):
            return None
        return os.path.realpath(candidate)
    except OSError:
        return None


# ────────────────────────────────────────────────────────────── Fingerprinting ──


@dataclass(frozen=True)
class Fingerprint:
    """What a device actually answers, used as a topology-free identity.

    ``blocks`` is the largest register block readable from address 0, and
    ``fc4`` records whether the device also answers function code 4. Together
    with the baud rate this is usually enough to separate sensor models — and
    when it is not, :func:`signature_conflicts` says so explicitly instead of
    letting the station guess.
    """

    baud: int
    blocks: int
    fc4: bool

    @property
    def key(self) -> str:
        return f"{self.baud}:{self.blocks}:{'fc4' if self.fc4 else 'fc3'}"

    @staticmethod
    def from_key(key: str) -> "Fingerprint | None":
        try:
            baud_raw, blocks_raw, fc_raw = key.split(":")
            return Fingerprint(int(baud_raw), int(blocks_raw), fc_raw == "fc4")
        except Exception:
            return None


@dataclass
class ProbeResult:
    """Outcome of probing one device at one baud rate."""

    device: str
    baud: int
    responded: bool
    fingerprint: Fingerprint | None = None
    register0: float | None = None
    error: str | None = None

    def summary(self) -> dict[str, Any]:
        return {
            "device": self.device,
            "baud": self.baud,
            "responded": self.responded,
            "signature": None if self.fingerprint is None else self.fingerprint.key,
            "register0": self.register0,
            "error": self.error,
        }


def _open_probe_instrument(device: str, baud: int) -> minimalmodbus.Instrument:
    instrument = minimalmodbus.Instrument(device, 1)
    instrument.serial.baudrate = baud
    instrument.serial.bytesize = 8
    instrument.serial.parity = serial.PARITY_NONE
    instrument.serial.stopbits = 1
    instrument.serial.timeout = PROBE_TIMEOUT_SECONDS
    instrument.mode = minimalmodbus.MODE_RTU
    # Always flush before probing: relay switching leaves garbage in the buffer
    # and a desynced RTU frame looks exactly like a dead sensor.
    instrument.clear_buffers_before_each_transaction = True
    instrument.close_port_after_each_call = False
    return instrument


def probe_device(device: str, baud: int) -> ProbeResult:
    """Probe one device at one baud rate. Never raises."""
    instrument: minimalmodbus.Instrument | None = None
    try:
        instrument = _open_probe_instrument(device, baud)
    except Exception as exc:
        return ProbeResult(device=device, baud=baud, responded=False, error=f"open failed: {exc}")

    try:
        register0: float | None = None
        blocks = 0
        for count in _PROBE_BLOCKS:
            try:
                values = instrument.read_registers(0, count, functioncode=3)
            except Exception:
                continue
            if values:
                blocks = count
                register0 = float(values[0])
                break

        if blocks == 0:
            # Nothing on FC3. Try FC4 before calling it dead — some radiation
            # sensors only implement input registers.
            try:
                register0 = float(instrument.read_register(0, 0, functioncode=4))
                return ProbeResult(
                    device=device,
                    baud=baud,
                    responded=True,
                    fingerprint=Fingerprint(baud=baud, blocks=1, fc4=True),
                    register0=register0,
                )
            except Exception as exc:
                return ProbeResult(
                    device=device, baud=baud, responded=False, error=f"no response: {exc}"
                )

        fc4 = False
        try:
            instrument.read_register(0, 0, functioncode=4)
            fc4 = True
        except Exception:
            fc4 = False

        return ProbeResult(
            device=device,
            baud=baud,
            responded=True,
            fingerprint=Fingerprint(baud=baud, blocks=blocks, fc4=fc4),
            register0=register0,
        )
    except Exception as exc:  # pragma: no cover - defensive
        return ProbeResult(device=device, baud=baud, responded=False, error=str(exc))
    finally:
        try:
            if instrument is not None and instrument.serial and instrument.serial.is_open:
                instrument.serial.close()
        except Exception:
            pass


def probe_all_bauds(device: str, bauds: Iterable[int] = (4800, 9600)) -> list[ProbeResult]:
    """Probe a device across candidate baud rates, stopping at the first hit."""
    results: list[ProbeResult] = []
    for baud in bauds:
        result = probe_device(device, baud)
        results.append(result)
        if result.responded:
            break
        # Let the transceiver settle before switching baud.
        time.sleep(0.05)
    return results


# ─────────────────────────────────────────────────────────── Signature storage ──


@dataclass
class SignatureStore:
    """Per-sensor fingerprints captured from known-good hardware.

    Stored as JSON so it can be committed, inspected and hand-edited. A sensor
    may legitimately have more than one signature (firmware revisions differ).
    """

    path: Path
    signatures: dict[str, list[str]] = field(default_factory=dict)

    @classmethod
    def load(cls, path: str | Path) -> "SignatureStore":
        target = Path(path)
        store = cls(path=target)
        try:
            if target.is_file():
                payload = json.loads(target.read_text(encoding="utf-8"))
                if isinstance(payload, dict):
                    for sensor, value in payload.items():
                        if sensor not in SENSOR_NAMES:
                            continue
                        if isinstance(value, str):
                            store.signatures[sensor] = [value]
                        elif isinstance(value, list):
                            store.signatures[sensor] = [str(item) for item in value if item]
        except Exception as exc:
            logger.warning("Could not read sensor signatures from %s: %s", target, exc)
        return store

    def save(self) -> None:
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text(
                json.dumps(self.signatures, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
        except Exception as exc:
            logger.warning("Could not write sensor signatures to %s: %s", self.path, exc)

    def record(self, sensor: str, fingerprint: Fingerprint) -> None:
        if sensor not in SENSOR_NAMES:
            raise ValueError(f"unknown sensor: {sensor}")
        existing = self.signatures.setdefault(sensor, [])
        if fingerprint.key not in existing:
            existing.append(fingerprint.key)

    def sensors_for(self, fingerprint: Fingerprint) -> list[str]:
        return [
            sensor
            for sensor, keys in self.signatures.items()
            if fingerprint.key in keys
        ]

    def conflicts(self) -> dict[str, list[str]]:
        """Signatures claimed by more than one sensor.

        These sensors cannot be told apart by probing and must be anchored by
        serial or topology instead.
        """
        owners: dict[str, list[str]] = {}
        for sensor, keys in self.signatures.items():
            for key in keys:
                owners.setdefault(key, []).append(sensor)
        return {key: sorted(names) for key, names in owners.items() if len(names) > 1}


def signature_conflicts(store: SignatureStore) -> dict[str, list[str]]:
    return store.conflicts()


# ──────────────────────────────────────────────────────────────── Resolution ──


def classify_pin(pin: str | None, device: str) -> tuple[str, str, str]:
    """Classify how trustworthy a configured pin is: (method, confidence, detail).

    A raw ``/dev/ttyUSB*`` node is the only genuinely untrustworthy case — the
    kernel assigns those in enumeration order. Anything else is a deliberate
    stable alias created by udev, so it is honoured:

    * ``/dev/serial/by-id/…``  — encodes the USB serial number → high
    * ``/dev/serial/by-path/…`` — encodes the hub topology → medium
    * any other symlink (e.g. ``/dev/rs485-rain`` from our own udev rules)
      → medium, because the admin declared it on purpose
    """
    if not pin:
        return "unresolved", "none", "no pin configured"

    if "/serial/by-id/" in pin:
        return "serial", "high", "USB serial alias (/dev/serial/by-id)"

    if "/serial/by-path/" in pin:
        return (
            "path",
            "medium",
            "USB topology path — re-verify after any hub re-enumeration",
        )

    # A raw kernel device node: numbering follows enumeration order, so this
    # cannot be trusted to be the same sensor after a reboot or re-plug.
    if pin == device and pin.startswith(_ADAPTER_PREFIXES):
        return (
            "pinned",
            "low",
            "raw device node — numbering is not stable across reboots; "
            "create a udev alias (python -m app.tools.ports udev)",
        )

    # A symlink we created (or the admin created) that resolves to a tty. It
    # only exists when its udev rule matched, so it fails closed by design.
    return "udev", "medium", f"udev alias {pin} -> {device}"


@dataclass
class Assignment:
    """The device chosen for one logical sensor, and how we got there."""

    sensor: str
    device: str | None
    method: str  # serial | fingerprint | path | pinned | unresolved
    confidence: str  # high | medium | low | none
    detail: str = ""
    adapter: Adapter | None = None

    @property
    def resolved(self) -> bool:
        return self.device is not None

    def summary(self) -> dict[str, Any]:
        return {
            "sensor": self.sensor,
            "device": self.device,
            "method": self.method,
            "confidence": self.confidence,
            "detail": self.detail,
            "by_path": None if self.adapter is None else self.adapter.by_path,
            "by_id": None if self.adapter is None else self.adapter.by_id,
        }


class PortResolver:
    """Maps logical sensors to device nodes, failing closed on ambiguity.

    ``pins`` are the configured ``*_PORT`` values (device, by-path or by-id).
    They are treated as hints: a pin that resolves and whose adapter carries a
    usable serial number is trusted outright; otherwise the resolver tries to
    confirm identity by fingerprint before accepting it.
    """

    def __init__(
        self,
        pins: dict[str, str | None],
        signatures: SignatureStore,
        *,
        strict: bool = True,
        probe_enabled: bool = True,
        exclude_devices: Iterable[str] = (),
    ) -> None:
        self.pins = {name: pins.get(name) for name in SENSOR_NAMES}
        self.signatures = signatures
        self.strict = strict
        self.probe_enabled = probe_enabled
        # Devices that must never be probed or assigned — the GPS receiver, in
        # particular, enumerates as ttyACM just like some RS-485 adapters.
        self.exclude_devices = list(exclude_devices)
        self.assignments: dict[str, Assignment] = {}
        self.last_resolved_at: float | None = None
        self.notes: list[str] = []

    # -- helpers ----------------------------------------------------------

    def _unresolved(self, sensor: str, detail: str) -> Assignment:
        return Assignment(
            sensor=sensor,
            device=None,
            method="unresolved",
            confidence="none",
            detail=detail,
        )

    def _adapter_for(self, adapters: list[Adapter], device: str) -> Adapter | None:
        for adapter in adapters:
            if adapter.device == device:
                return adapter
        return None

    # -- main -------------------------------------------------------------

    def resolve(self) -> dict[str, Assignment]:
        """Resolve every sensor. Never raises; unresolved sensors are reported."""
        self.notes = []
        adapters = sensor_adapters(self.exclude_devices)
        if not adapters:
            self.notes.append("no USB serial adapters present")
            self.assignments = {
                name: self._unresolved(name, "no serial adapters present")
                for name in SENSOR_NAMES
            }
            self.last_resolved_at = time.time()
            return self.assignments

        assignments: dict[str, Assignment] = {}
        claimed: set[str] = set()

        # ── Pass 1: pins anchored on a usable USB serial number ───────────
        # by-id encodes the serial, so a pin that resolves through by-id (or an
        # adapter that reports its own serial) is trustworthy without probing.
        for sensor in SENSOR_NAMES:
            device = resolve_alias(self.pins.get(sensor))
            if device is None or device in claimed:
                continue
            adapter = self._adapter_for(adapters, device)
            if adapter is None or not adapter.has_usable_serial:
                continue
            assignments[sensor] = Assignment(
                sensor=sensor,
                device=device,
                method="serial",
                confidence="high",
                detail=f"USB serial {adapter.serial_number}",
                adapter=adapter,
            )
            claimed.add(device)

        # ── Pass 2: fingerprint discovery ─────────────────────────────────
        # Topology-independent, so this survives a hub re-enumeration. Only
        # unambiguous matches are accepted.
        if self.probe_enabled and self.signatures.signatures:
            free_adapters = [a for a in adapters if a.device not in claimed]
            matches: dict[str, list[Adapter]] = {}
            for adapter in free_adapters:
                results = probe_all_bauds(adapter.device)
                hit = next((r for r in results if r.responded and r.fingerprint), None)
                if hit is None or hit.fingerprint is None:
                    continue
                for sensor in self.signatures.sensors_for(hit.fingerprint):
                    if sensor in assignments:
                        continue
                    matches.setdefault(sensor, []).append(adapter)

            for sensor, candidates in matches.items():
                unique = [a for a in candidates if a.device not in claimed]
                if len(unique) != 1:
                    if len(unique) > 1:
                        self.notes.append(
                            f"{sensor}: {len(unique)} devices share its signature; "
                            "cannot identify by probing"
                        )
                    continue
                adapter = unique[0]
                assignments[sensor] = Assignment(
                    sensor=sensor,
                    device=adapter.device,
                    method="fingerprint",
                    confidence="high",
                    detail="matched captured signature",
                    adapter=adapter,
                )
                claimed.add(adapter.device)

        # ── Pass 3: topology pins ─────────────────────────────────────────
        # Last resort. Confidence is medium because a cascaded hub can shift
        # these paths between boots.
        for sensor in SENSOR_NAMES:
            if sensor in assignments:
                continue
            pin = self.pins.get(sensor)
            device = resolve_alias(pin)
            if device is None:
                assignments[sensor] = self._unresolved(
                    sensor,
                    "no pin configured" if not pin else f"configured port not present: {pin}",
                )
                continue
            if device in claimed:
                assignments[sensor] = self._unresolved(
                    sensor, f"{device} already assigned to another sensor"
                )
                continue
            adapter = self._adapter_for(adapters, device)
            method, confidence, detail = classify_pin(pin, device)
            assignments[sensor] = Assignment(
                sensor=sensor,
                device=device,
                method=method,
                confidence=confidence,
                detail=detail,
                adapter=adapter,
            )
            claimed.add(device)

        self.assignments = assignments
        self.last_resolved_at = time.time()

        for sensor, assignment in assignments.items():
            if not assignment.resolved:
                logger.warning("Sensor %s unresolved: %s", sensor, assignment.detail)
            elif assignment.confidence == "low":
                logger.warning(
                    "Sensor %s bound to %s by %s (%s) — identity is not guaranteed",
                    sensor,
                    assignment.device,
                    assignment.method,
                    assignment.detail,
                )
            else:
                logger.info(
                    "Sensor %s -> %s via %s (%s)",
                    sensor,
                    assignment.device,
                    assignment.method,
                    assignment.detail,
                )
        return assignments

    def device_for(self, sensor: str) -> str | None:
        """Device to read for a sensor, or None when it must not be read.

        In strict mode a low-confidence binding is refused: publishing a value
        that may belong to a different sensor is worse than publishing null.
        """
        assignment = self.assignments.get(sensor)
        if assignment is None or not assignment.resolved:
            return None
        if self.strict and assignment.confidence == "low":
            return None
        return assignment.device

    def status(self) -> dict[str, Any]:
        return {
            "strict": self.strict,
            "probe_enabled": self.probe_enabled,
            "last_resolved_at": self.last_resolved_at,
            "notes": list(self.notes),
            "signature_conflicts": self.signatures.conflicts(),
            "assignments": {
                name: assignment.summary()
                for name, assignment in sorted(self.assignments.items())
            },
        }


# ───────────────────────────────────────────────────────────── udev rule text ──


def udev_rules(adapters_by_sensor: dict[str, Adapter]) -> str:
    """Generate udev rules pinning each sensor to a stable ``/dev/rs485-*`` name.

    Prefers the adapter's serial number when it has one (survives re-plugging
    anywhere), and falls back to the kernel USB path otherwise.

    Install with::

        sudo cp 99-cropconnect-rs485.rules /etc/udev/rules.d/
        sudo udevadm control --reload-rules && sudo udevadm trigger
    """
    lines = [
        "# CropConnect RS-485 adapter pinning.",
        "# Generated by: python -m app.tools.ports udev",
        "#",
        "# Each rule creates a stable /dev/rs485-<sensor> symlink. Point the",
        "# matching *_PORT entry in .env at that symlink.",
        "",
    ]
    for sensor in SENSOR_NAMES:
        adapter = adapters_by_sensor.get(sensor)
        if adapter is None:
            lines.append(f'# {sensor}: no adapter recorded — rule not generated')
            continue

        vid = f"{adapter.vid:04x}" if adapter.vid is not None else None
        pid = f"{adapter.pid:04x}" if adapter.pid is not None else None
        match = ['SUBSYSTEM=="tty"']
        if vid and pid:
            match.append(f'ATTRS{{idVendor}}=="{vid}"')
            match.append(f'ATTRS{{idProduct}}=="{pid}"')

        if adapter.has_usable_serial:
            match.append(f'ATTRS{{serial}}=="{adapter.serial_number}"')
            note = "anchored on USB serial — survives moving to any socket"
        elif adapter.location:
            # pyserial location looks like "1-1.4.4.3.2:1.0"; udev KERNELS wants
            # the device part without the interface suffix.
            kernels = adapter.location.split(":")[0]
            match.append(f'KERNELS=="{kernels}"')
            note = "anchored on hub socket — keep this adapter in that socket"
        else:
            lines.append(
                f'# {sensor}: adapter has no serial and no USB path — cannot pin'
            )
            continue

        lines.append(f"# {sensor}: {note}")
        lines.append(", ".join(match) + f', SYMLINK+="rs485-{sensor.replace("_", "-")}"')
        lines.append("")
    return "\n".join(lines)
