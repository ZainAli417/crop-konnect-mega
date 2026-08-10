# Sensor identity and port stability

## The problem, stated precisely

Every sensor on this station is a Modbus-RTU device with **slave id 1** answering
on **holding register 0**. Four of the five also share **4800 baud**:

| sensor | baud | slave | register | distinguishable by protocol? |
|---|---|---|---|---|
| wind speed | 4800 | 1 | 0 | no |
| wind direction | 4800 | 1 | 0 | no |
| rain | 4800 | 1 | 0 | no |
| solar / UV | 4800 | 1 | 0 | no |
| soil | 9600 | 1 | 0–6 | **yes** (different baud, 7 registers) |

So when you plug the wind-direction sensor into the adapter the code calls
"wind speed", it answers perfectly — as wind speed. **No register read can
detect this.** The sensor is not wrong and the code is not wrong; the *binding*
between logical sensor and device node is wrong.

`/dev/ttyUSB*` numbering follows enumeration order, which is not stable. That is
the whole bug.

## Why `by-id` and `by-path` did not fix it

- **`/dev/serial/by-id`** encodes the adapter's USB serial number. Most CH340
  clones ship without one, so all five adapters collapse to the same name.
- **`/dev/serial/by-path`** encodes the USB topology. This is the right idea, and
  your `.env` already used it — but comparing your two saved configs shows the
  topology itself moved:

  | sensor | `.env.save` | `.env.save.1` |
  |---|---|---|
  | rain | `…usb-0:1.4.4.3.4:1.0` | `…usb-0:1.4.4.3.3:1.0` |
  | solar | `…usb-0:1.4.4.3:1.0` | `…usb-0:1.4.4.3.2:1.0` |

  Solar went from a 4-level path to a 5-level one. That means an intermediate hub
  in the cascaded powered hub enumerated inconsistently between boots, shifting
  every path below it. On a Pi with a single DWC-OTG root hub and stacked hubs
  this is common, especially under brownout.

**Conclusion:** on this hardware, topology alone is not a sufficient anchor.

## What the backend does now

`app/serial_ports.py` resolves each sensor through three anchors, best first:

1. **`serial`** — the adapter's USB iSerial. Survives moving to any socket.
2. **`fingerprint`** — probe the device and match a signature captured from the
   known-good sensor (baud + readable register-block size + FC4 support).
   Topology-independent, so it survives a hub re-enumeration.
3. **`path`** — the `by-path` pin from `.env`. Accepted, but only at *medium*
   confidence.

A raw `/dev/ttyUSB*` pin is *low* confidence. With
`SENSOR_STRICT_IDENTITY=true` (the default) a low-confidence sensor is **not
read at all** — the station publishes `null` for it.

That is deliberate: a null gap in a chart is recoverable, a UV reading stored as
rainfall silently corrupts your history and every DSS run built on it.

Check the current state any time:

```
curl -s localhost:8000/health | python -m json.tool     # look at serial_reader.identity
```

## Setting it up — do this once, in order

Stop the backend first so the ports are free:

```bash
sudo systemctl stop cropconnect          # or however uvicorn is started
cd ~/crop-konnect-mega-raspberypi
source .venv/bin/activate
```

### 1. Do your adapters have serial numbers?

```bash
python -m app.tools.ports list
```

If the `anchorable` column says `yes` for all five, you are done in one step:
generate the udev rules (step 4) and skip fingerprinting entirely. If it says
`NO` for everything — the usual CH340 outcome — continue.

### 2. Find out which sensors are distinguishable by probing

```bash
python -m app.tools.ports probe
```

This reports each adapter's signature, e.g. `4800:2:fc3` (4800 baud, 2 readable
registers, no FC4). Read the summary at the bottom:

- **All signatures unique** → fingerprinting alone will identify everything.
  Go to step 3.
- **Some share a signature** → those specific sensors cannot be told apart by
  software. They must be anchored physically (step 4).

### 3. Teach the station each sensor's fingerprint

Connect **one** sensor at a time — this is the same bench setup you already use
to test sensors individually — and capture it:

```bash
python -m app.tools.ports capture --sensor wind_speed
python -m app.tools.ports capture --sensor wind_direction
python -m app.tools.ports capture --sensor rain
python -m app.tools.ports capture --sensor solar
python -m app.tools.ports capture --sensor soil
```

With several adapters connected, pass `--device /dev/ttyUSB1` explicitly.
Signatures are written to `sensor_signatures.json` (path configurable via
`SENSOR_SIGNATURE_FILE`). Commit that file — it is hardware fact, not secret.

The command warns you if two sensors claim the same signature.

### 4. Pin whatever fingerprinting cannot separate

```bash
python -m app.tools.ports udev -o 99-cropconnect-rs485.rules
sudo cp 99-cropconnect-rs485.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

This creates stable names — `/dev/rs485-wind-speed`, `/dev/rs485-rain`, … —
anchored on the adapter's serial where it has one, and on its **hub socket**
otherwise. Then point `.env` at those names:

```
WIND_SPEED_PORT=/dev/rs485-wind-speed
WIND_DIRECTION_PORT=/dev/rs485-wind-direction
SOIL_PORT=/dev/rs485-soil
RAIN_PORT=/dev/rs485-rain
SOLAR_PORT=/dev/rs485-solar
```

Socket-anchored rules only hold while each adapter stays in the socket it was in
when you generated them. **Label the hub sockets physically.** If a symlink is
missing at boot the sensor publishes null and says so — it never silently reads
the wrong device.

### 5. Confirm

```bash
python -m app.tools.ports doctor
```

Every sensor should read `will read`. Anything showing `WILL PUBLISH NULL`
explains itself in the verdict column. Then restart the backend.

## The fix that removes this problem permanently

Everything above is mitigation for one root cause: **five devices sharing slave
id 1.** If any of these sensors can be re-addressed — most RS-485 sensors of this
class expose a writable slave-address register even when the datasheet calls the
default "fixed" — then give each a unique id (1–5). At that point:

- all five can share **one** RS-485 bus and **one** USB adapter;
- identity comes from the slave id, which is in the sensor itself;
- port naming stops mattering entirely, and four adapters plus the hub cascade
  disappear from the failure surface.

Worth 20 minutes with a datasheet before investing further in port pinning.
Note that the soil sensor still needs its own adapter unless it can also be
moved to 4800 baud, since one bus runs at one baud rate.

## Failure isolation

Separate from identity, one unresponsive sensor could previously take the whole
service down. Causes and fixes:

| cause | fix |
|---|---|
| `minimalmodbus` is blocking and ran directly on the asyncio event loop, so a stuck port froze uvicorn and every HTTP request with it | reads now run via `asyncio.to_thread` under `asyncio.wait_for` with `SENSOR_READ_TIMEOUT_SECONDS` (default 6s) |
| solar held its port open and skipped the buffer flush, so relay-switching garbage desynced the RTU frame and a re-enumerated adapter left a dead file descriptor | `clear_buffers_before_each_transaction` and `close_port_after_each_call` are now both `True` everywhere — this is the intermittent solar/rain failure |
| a single dropped frame put a sensor straight into 30s backoff | now requires `SENSOR_FAILURE_THRESHOLD` (default 3) consecutive failures |
| a read abandoned by timeout could overlap the next read on the same port | one lock per port; an overlapping read is skipped, not queued |

Relay control was **not** touched — pins, active-low handling, settle and
stabilize timing, and group sequencing are exactly as they were.

## Database load

The pollers used to call `load_runtime_settings()` on a fresh session every
`SETTINGS_REFRESH_INTERVAL_SECONDS` (default 1s) for the whole of every sleep —
two SELECTs plus a possible COMMIT, plus a `SELECT 1` from `pool_pre_ping`, from
*two* pollers independently. Roughly six to eight round trips per second to the
Supabase pooler, forever, for settings that change when a human taps a toggle.

`app/settings_cache.py` replaces that with one shared TTL cache
(`SETTINGS_CACHE_TTL_SECONDS`, default 15s):

- a full load populates it;
- refreshes read only `station_settings.updated_at` and reuse the cached object
  unless it moved;
- a settings `PATCH` invalidates it, so app toggles still apply next cycle;
- a database blip serves the last known-good value instead of flapping the
  station into "everything disabled".

Per-reading writes were trimmed too: the settings row is ensured once per
process rather than per reading, `received_at` is set in Python so the response
does not need a read-back, and the two `db.refresh()` calls after insert are
gone. A dead `load_runtime_settings()` call in the irrigation path was removed.

Watch the effect at `/health` under `serial_reader.settings_cache`
(`full_loads` / `change_checks` / `cache_hits`).
