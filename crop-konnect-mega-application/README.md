# CropConnect Sensor Backend (Raspberry Pi)

FastAPI service that reads the weather station's RS-485 sensors over USB, writes
readings to Supabase, serves them to the mobile app, and switches sensor power
through GPIO relays.

- Deep dive on port identity and failure isolation: **[docs/SENSOR_PORTS.md](docs/SENSOR_PORTS.md)**
- Final env template: **`.env.example2`**

> **Read this first.** All five sensors are Modbus devices with **slave id 1** on
> **register 0**, and four of them also share **4800 baud**. They are
> protocol-identical, so if the wrong adapter is bound to "rain" it answers
> perfectly — as rain. Linux does not name USB adapters consistently, so the
> setup below is about proving *which adapter is which*. It is not optional.

---

# Part 1 — First-time setup

Follow the steps in order. **Step 4 has two branches** and which one you take
depends on what Step 3 prints. Do not skip Step 3.

## Step 0 — Install

```bash
cd ~/crop-konnect-mega-raspberypi
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Step 1 — Create your `.env`

```bash
cp .env.example2 .env
nano .env
```

Edit only the two `TODO` lines:

1. `DATABASE_URL` — your Supabase password. **A literal `$` must be written as `$$`.**
2. `INGEST_API_KEY` and `ADMIN_API_KEY` — any long random strings.

Leave the sensor port lines alone for now. Step 4 sets them.

## Step 2 — Stop the service so the serial ports are free

Every command below talks to the sensors directly. If the backend is running it
holds the ports and every sensor will look dead.

```bash
sudo systemctl stop cropconnect      # use your actual service name
```

Not running as a service yet? Just make sure no `uvicorn` is alive:

```bash
pkill -f uvicorn ; sleep 1
```

## Step 3 — Find out if your adapters are anchorable

```bash
python -m app.tools.ports list
```

```
device         use           usb serial  anchorable  usb path   description
-------------  ------------  ----------  ----------  ---------  ------------------
/dev/ttyACM0   GPS (skip)    -           NO          3-1:1.0    u-blox 7 - GPS/GNSS
/dev/ttyAMA10  not a sensor  -           NO          -          n/a
/dev/ttyS0     not a sensor  -           NO          -          n/a
/dev/ttyUSB0   sensor        -           NO          1-1.1      USB Serial
/dev/ttyUSB1   sensor        -           NO          1-1.3      USB Serial
/dev/ttyUSB2   sensor        -           NO          1-1.4.2    USB Serial
/dev/ttyUSB3   sensor        -           NO          1-1.4.4    USB Serial
/dev/ttyUSB4   sensor        -           NO          1-1.4.3.4  USB Serial
```

The **`use`** column matters as much as the rest. Only rows marked `sensor` are
ever probed:

- `GPS (skip)` — your u-blox receiver. It enumerates as `ttyACM` exactly like
  some RS-485 adapters do, so it is excluded by device (from `GPS_PORT`).
- `not a sensor` — the Pi's built-in UARTs (`ttyAMA*`, `ttyS*`).

If your GPS shows as `sensor` instead of `GPS (skip)`, set `GPS_PORT` in `.env`
to its device before continuing.

**Now look at the `anchorable` column for the `sensor` rows only, then read the
summary line underneath.**

| Summary line you see | Meaning | Go to |
|---|---|---|
| `GOOD: all N sensor adapters report a usable serial number.` | every adapter has a unique USB serial | **Step 4A** |
| `NONE of the sensor adapters report a usable serial number.` | normal for CH340 clones | **Step 4B** |
| `PARTIAL: X of N sensor adapters have a usable serial.` | mixed | **Step 4B** (it covers both) |

The `Configured pins` block at the bottom will say `MISSING` for all five at this
point. That is expected — the `/dev/rs485-*` names do not exist until Step 4
creates them.

---

## Step 4A — Adapters ARE anchorable

The easy path. Identity comes from each adapter's USB serial, so it survives
reboots **and** moving adapters between hub sockets.

### 4A.1 — Tell the tool which sensor is on which adapter

The rule generator reads your current `*_PORT` pins, so set them once:

```bash
nano .env
```

```
WIND_SPEED_PORT=/dev/ttyUSB0
WIND_DIRECTION_PORT=/dev/ttyUSB1
SOIL_PORT=/dev/ttyUSB2
RAIN_PORT=/dev/ttyUSB3
SOLAR_PORT=/dev/ttyUSB4
```

**Confirm every guess before continuing.** Probe one adapter at a time:

```bash
python -m app.tools.ports probe --device /dev/ttyUSB0
```

- `baud 9600` with `regs 7` → that is the **soil** sensor, guaranteed.
- `baud 4800` → one of the other four. Tell them apart with your standalone
  scripts by editing their `PORT` line: `wind_speed.py`, `Wind direction.py`,
  `IR_Rain.py`, `uv.py`.

### 4A.2 — Generate and install the udev rules

```bash
python -m app.tools.ports udev -o 99-cropconnect-rs485.rules
cat 99-cropconnect-rs485.rules       # each rule should say "anchored on USB serial"

sudo cp 99-cropconnect-rs485.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### 4A.3 — Verify the stable names exist

```bash
ls -l /dev/rs485-*
```

All five must appear:

```
/dev/rs485-wind-speed      -> ttyUSB0
/dev/rs485-wind-direction  -> ttyUSB1
/dev/rs485-soil            -> ttyUSB2
/dev/rs485-rain            -> ttyUSB3
/dev/rs485-solar           -> ttyUSB4
```

Missing one? Its rule did not match. Re-run `list`, confirm that adapter still
reports a serial, and regenerate.

### 4A.4 — Point `.env` at the stable names

```
WIND_SPEED_PORT=/dev/rs485-wind-speed
WIND_DIRECTION_PORT=/dev/rs485-wind-direction
SOIL_PORT=/dev/rs485-soil
RAIN_PORT=/dev/rs485-rain
SOLAR_PORT=/dev/rs485-solar
```

Go to **Step 5**.

> Optional but recommended: also do **4B.2** (fingerprint capture). Five minutes,
> and it gives you a second independent anchor if an adapter ever dies.

---

## Step 4B — Adapters are NOT anchorable

Your CH340 adapters report no unique serial, so `/dev/serial/by-id` cannot work —
this is exactly why your earlier attempt failed. You will use **fingerprinting**
(software identity) for whatever it can separate, and **hub-socket pinning** for
the rest.

### 4B.1 — Find out which sensors are distinguishable

Plug everything in, then:

```bash
python -m app.tools.ports probe
```

```
device         baud   regs   fc4   signature / value
-------------  -----  -----  ----  ---------------------
/dev/ttyUSB0   9600   7      no    9600:7:fc3   reg0=213
/dev/ttyUSB1   4800   2      no    4800:2:fc3   reg0=0
/dev/ttyUSB2   4800   1      no    4800:1:fc3   reg0=6
/dev/ttyUSB3   4800   1      no    4800:1:fc3   reg0=0
/dev/ttyUSB4   4800   1      yes   4800:1:fc4   reg0=412
```

**Read the summary at the bottom — this is the decision point:**

| Summary | What it means | What to do |
|---|---|---|
| `Every responding adapter has a unique signature.` | software can identify all five | do **4B.2**, then **skip 4B.3 entirely** |
| `Devices sharing a signature (NOT distinguishable by probing): …` | those specific devices cannot be told apart | do **4B.2** for all sensors, then **4B.3** for the listed ones only |

In the example above `/dev/ttyUSB2` and `/dev/ttyUSB3` both show `4800:1:fc3`, so
those two need 4B.3. The other three are fully handled by 4B.2.

### 4B.2 — Capture each sensor's fingerprint

Do this **one sensor at a time** — the same bench setup you already use to test
sensors individually. Connect only that sensor, then:

```bash
python -m app.tools.ports capture --sensor soil
python -m app.tools.ports capture --sensor wind_speed
python -m app.tools.ports capture --sensor wind_direction
python -m app.tools.ports capture --sensor rain
python -m app.tools.ports capture --sensor solar
```

With several adapters connected you must say which one:

```bash
python -m app.tools.ports capture --sensor rain --device /dev/ttyUSB3
```

Each run prints the captured signature and warns you if two sensors end up
claiming the same one. Results go to `sensor_signatures.json` — **commit that
file**, it is hardware fact, not a secret.

### 4B.3 — Pin the sensors fingerprinting cannot separate

Only for the colliding devices from 4B.1.

**a. Set `.env` pins to the correct device for each sensor**, so the generator
knows the mapping. Your existing `by-path` values are fine here (they are kept
commented in `.env.example2`), or use raw `/dev/ttyUSB*`. Verify each one with
your standalone scripts first.

**b. Generate and install:**

```bash
python -m app.tools.ports udev -o 99-cropconnect-rs485.rules
cat 99-cropconnect-rs485.rules      # colliding ones say "anchored on hub socket"

sudo cp 99-cropconnect-rs485.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
ls -l /dev/rs485-*
```

**c. ⚠️ Physically label the hub sockets.** A socket-anchored rule only holds
while that adapter stays in that socket. Put tape or a sticker on each one:
`WS`, `WD`, `SOIL`, `RAIN`, `SOLAR`. If an adapter is re-plugged elsewhere its
symlink disappears and that sensor publishes `null` — it will **never** silently
read the wrong sensor.

**d. Point `.env` at the stable names:**

```
WIND_SPEED_PORT=/dev/rs485-wind-speed
WIND_DIRECTION_PORT=/dev/rs485-wind-direction
SOIL_PORT=/dev/rs485-soil
RAIN_PORT=/dev/rs485-rain
SOLAR_PORT=/dev/rs485-solar
```

Go to **Step 5**.

---

## Step 5 — Verify before starting the service

```bash
python -m app.tools.ports doctor
```

```
sensor            device                 method       confidence  verdict
----------------  ---------------------  -----------  ----------  ----------
wind_speed        /dev/ttyUSB1           fingerprint  high        will read
wind_direction    /dev/ttyUSB2           serial       high        will read
soil              /dev/ttyUSB0           fingerprint  high        will read
rain              /dev/ttyUSB3           path         medium      will read
solar             /dev/ttyUSB4           fingerprint  high        will read
```

**All five must say `will read`.** Anything saying `WILL PUBLISH NULL` explains
itself in the verdict column — that is the safety guard doing its job, not a bug.

| Verdict / cause | Fix |
|---|---|
| `no pin configured` | set that sensor's `*_PORT` in `.env` |
| `configured port not present: …` | symlink missing — check `ls -l /dev/rs485-*`, redo Step 4 |
| `identity not confirmed`, confidence `low` | the pin is a raw `/dev/ttyUSB*`; finish Step 4 so it becomes `serial`, `fingerprint` or `path` |
| `already assigned to another sensor` | two sensors point at the same device — fix the `.env` pins |
| `N devices share its signature` | those sensors need Step 4B.3 socket pinning |

## Step 6 — Start the service and confirm live

```bash
sudo systemctl start cropconnect
sleep 20
curl -s localhost:8000/health | python -m json.tool
```

Check three things in the output:

1. `serial_reader.identity.assignments` — every sensor has a `device`, and
   `confidence` is `high` or `medium`.
2. `serial_reader.sensor_failures` — all zeros after a few cycles.
3. `serial_reader.settings_cache` — `full_loads` stays low (single digits) while
   `cache_hits` climbs. That confirms the database is no longer polled every
   second.

Then confirm rows are landing in Supabase:

```bash
curl -s localhost:8000/api/v1/stations/RPAWTEX/latest | python -m json.tool
```

---

# Part 2 — Day-to-day operations

## A sensor suddenly reads `null`

That is the fail-closed guard: the backend could not prove which sensor is on
that port, so it published nothing rather than risk storing a UV value as
rainfall.

```bash
sudo systemctl stop cropconnect
python -m app.tools.ports doctor      # the verdict column says exactly why
```

Most common cause: an adapter was moved to a different hub socket. Put it back in
its labelled socket, or redo Step 4.

## You swapped or added an adapter

1. `python -m app.tools.ports list` — does the new one have a serial?
2. `python -m app.tools.ports capture --sensor <name> --device <device>`
3. If it needs socket pinning, redo Step 4B.3.

The backend also re-resolves identity every `SENSOR_IDENTITY_RECHECK_SECONDS`
(default 300), so a hot-plug is often picked up without a restart.

## Command reference

| Command | What it does |
|---|---|
| `python -m app.tools.ports list` | adapters + whether they are anchorable |
| `python -m app.tools.ports probe` | live fingerprint of every adapter |
| `python -m app.tools.ports probe --device /dev/ttyUSB0` | probe one adapter |
| `python -m app.tools.ports capture --sensor rain` | teach the station one sensor |
| `python -m app.tools.ports doctor` | per-sensor will-read verdict |
| `python -m app.tools.ports status` | same, as JSON |
| `python -m app.tools.ports udev -o FILE` | generate udev rules |

## The permanent fix worth checking

All five sensors sharing **slave id 1** is the root cause of everything above.
Most RS-485 sensors of this class have a *writable* slave-address register even
when the datasheet calls the default "fixed".

If you can give each sensor a unique id (1–5):

- the four 4800-baud sensors share **one** bus and **one** USB adapter;
- identity lives in the sensor itself, so port naming stops mattering forever;
- the hub cascade leaves your failure surface entirely.

Twenty minutes with the datasheets. Soil still needs its own adapter unless it
can also move to 4800 baud, since one bus runs at one baud rate.

---

# Part 3 — Key `.env` settings

Fully annotated list in `.env.example2`. The ones that matter most:

| Key | Default | Why you would change it |
|---|---|---|
| `SENSOR_STRICT_IDENTITY` | `true` | `false` reads low-confidence ports anyway. **Debugging wiring only** — it re-enables mislabelled data. |
| `SENSOR_FINGERPRINT_ENABLED` | `true` | `false` skips probe-based identity (startup a few seconds faster) |
| `SENSOR_SIGNATURE_FILE` | `sensor_signatures.json` | where captures are stored |
| `SENSOR_IDENTITY_RECHECK_SECONDS` | `300` | `0` disables re-resolution after startup |
| `SENSOR_READ_TIMEOUT_SECONDS` | `6` | hard deadline per sensor; raise only if one is genuinely slow |
| `SENSOR_FAILURE_THRESHOLD` | `3` | consecutive failures before 30s backoff |
| `SETTINGS_CACHE_TTL_SECONDS` | `15` | how long settings are cached; a PATCH invalidates it anyway |

Relay keys (`RELAY_*`) are tuned — leave them alone.

---

# Part 4 — What was hardened (and what was not)

| Problem | Fix |
|---|---|
| Wrong sensor read under another sensor's name | three-anchor identity resolution that **fails closed** (`app/serial_ports.py`) |
| One dead sensor took the whole API down | blocking Modbus I/O moved off the event loop with a hard per-sensor deadline |
| Solar / rain crashing intermittently | solar no longer holds its port open or skips the buffer flush — relay-switching garbage was desyncing the RTU frame |
| A single dropped frame triggered 30s backoff | now needs `SENSOR_FAILURE_THRESHOLD` consecutive failures |
| ~6–8 DB round trips per second, forever | one shared TTL settings cache (`app/settings_cache.py`), invalidated on PATCH |
| Extra SELECTs on every reading insert | settings row ensured once per process; `received_at` set in Python; two `db.refresh()` calls dropped |

**Not touched:** all relay logic — pins, active-low handling, settle and
stabilize timing, and group sequencing are exactly as they were tuned.

---

# Part 5 — API reference

## Health

`GET /health` — includes `serial_reader.identity`, `sensor_failures` and
`settings_cache`.

## Serial runtime status

`GET /api/v1/runtime/serial`

## Ingest a reading

`POST /api/v1/ingest/readings` with header `X-API-Key: <INGEST_API_KEY>`

```json
{
  "device_id": "RPAWTEX",
  "station_name": "Field Station 1",
  "recorded_at": "2026-03-30T08:10:00Z",
  "data": {
    "ws": 4.1,
    "wd_deg": 90,
    "wd_dir": "E",
    "moist": 33.2,
    "temp": 29.4,
    "ec": 1200,
    "n": 10,
    "p": 12,
    "k": 20,
    "ph": 6.7,
    "rain": 0.0,
    "solar": 540
  }
}
```

Use ISO UTC timestamps like `2026-03-30T08:10:00Z`.

## Reads

- `GET /api/v1/stations/RPAWTEX/latest`
- `GET /api/v1/stations/RPAWTEX/readings?limit=200`
  — optional `recorded_from=2026-03-30T00:00:00Z`, `recorded_to=2026-03-30T23:59:59Z`
- `GET /api/v1/stations/RPAWTEX/summary?hours=24`

## Settings

- `GET /api/v1/stations/{device_id}/settings`
- `PATCH /api/v1/stations/{device_id}/settings` — invalidates the settings cache,
  so an app toggle applies on the next poll cycle

## Live stream

`ws://<pi-address>:8000/ws/stations/RPAWTEX`
