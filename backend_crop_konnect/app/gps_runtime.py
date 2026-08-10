from __future__ import annotations

import asyncio
import logging
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from geopy.distance import geodesic
from geopy.exc import GeocoderTimedOut
from geopy.geocoders import Nominatim
import pynmea2
import serial

from app.config import Settings, get_settings
from app.db import SessionLocal
from app.services import create_gps_fix_sync, get_or_create_station, run_broadcast


logger = logging.getLogger(__name__)

SERIAL_TIMEOUT = 1.0


def _empty_state() -> dict[str, Any]:
    return {
        "fix": False,
        "latitude": None,
        "longitude": None,
        "altitude_m": None,
        "speed_kmh": None,
        "heading_deg": None,
        "satellites": None,
        "nmea_time": None,
        "address": None,
        "recorded_at": None,
        "received_at": None,
        "moved_meters": None,
    }


@dataclass
class GpsReadingCache:
    current: dict[str, Any] = field(default_factory=_empty_state)
    latest: dict[str, Any] = field(default_factory=_empty_state)
    last_error: str | None = None
    updated_at: datetime | None = None
    _lock: threading.Lock = field(default_factory=threading.Lock, init=False, repr=False)

    def update_current(self, payload: dict[str, Any]) -> None:
        with self._lock:
            self.current = {**_empty_state(), **payload}
            self.updated_at = datetime.now(timezone.utc)
            self.last_error = None

    def update_latest(self, payload: dict[str, Any]) -> None:
        with self._lock:
            self.latest = {**_empty_state(), **payload}
            self.updated_at = datetime.now(timezone.utc)
            self.last_error = None

    def mark_error(self, error: str) -> None:
        with self._lock:
            self.last_error = error
            self.updated_at = datetime.now(timezone.utc)

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            return {
                "current": {**self.current},
                "latest": {**self.latest},
                "last_error": self.last_error,
                "updated_at": self.updated_at,
            }


class GpsTracker:
    def __init__(
        self,
        settings: Settings | None = None,
        cache: GpsReadingCache | None = None,
    ) -> None:
        self.settings = settings or get_settings()
        self.cache = cache or GpsReadingCache()
        self.running = False
        self.task: asyncio.Task | None = None
        self.serial: serial.Serial | None = None
        self.geolocator = Nominatim(user_agent="cropconnect_gps_tracker")
        self._working_state = _empty_state()
        self._last_geocode_at: datetime | None = None

    def status(self) -> dict[str, Any]:
        return {
            "enabled": self.settings.gps_reader_enabled,
            "running": self.running,
            "port": self.settings.gps_port,
            "baudrate": self.settings.gps_baud_rate,
            "min_move_meters": self.settings.gps_min_move_meters,
            "reverse_geocode_interval_seconds": self.settings.gps_reverse_geocode_interval_seconds,
            "cache": self.cache.snapshot(),
        }

    def ensure_station_record(self) -> None:
        db = SessionLocal()
        try:
            station = get_or_create_station(db, self.settings.device_id, self.settings.station_name)
            db.commit()
            db.refresh(station)
        except Exception as exc:
            db.rollback()
            logger.warning("GPS station ensure failed for %s: %s", self.settings.device_id, exc)
        finally:
            db.close()

    async def start(self) -> None:
        if not self.settings.gps_reader_enabled or self.running:
            return
        self.ensure_station_record()
        self.running = True
        self.task = asyncio.create_task(self._run_loop())
        logger.info("GPS tracker started for device %s on %s", self.settings.device_id, self.settings.gps_port)

    async def stop(self) -> None:
        self.running = False
        if self.task:
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass
            self.task = None
        if self.serial:
            try:
                if self.serial.is_open:
                    self.serial.close()
            except Exception:
                pass
            self.serial = None

    async def _run_loop(self) -> None:
        while self.running:
            try:
                await self._poll_port()
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                self.cache.mark_error(str(exc))
                logger.exception("GPS tracker error: %s", exc)
                if self.running:
                    await asyncio.sleep(5)

    async def _poll_port(self) -> None:
        try:
            self.serial = serial.Serial(self.settings.gps_port, baudrate=self.settings.gps_baud_rate, timeout=SERIAL_TIMEOUT)
        except Exception as exc:
            self.cache.mark_error(str(exc))
            logger.warning("Failed to open GPS port %s: %s", self.settings.gps_port, exc)
            await asyncio.sleep(5)
            return

        try:
            while self.running and self.serial and self.serial.is_open:
                line = await asyncio.to_thread(self.serial.readline)
                if not line:
                    continue

                decoded = line.decode("ascii", errors="replace").strip()
                if not decoded:
                    continue

                await self._handle_sentence(decoded)
        finally:
            try:
                if self.serial and self.serial.is_open:
                    self.serial.close()
            except Exception:
                pass
            self.serial = None

    async def _handle_sentence(self, sentence: str) -> None:
        if not sentence.startswith(("$GPGGA", "$GNGGA", "$GPRMC", "$GNRMC")):
            return

        try:
            msg = pynmea2.parse(sentence)
        except pynmea2.ParseError:
            return
        except Exception as exc:
            self.cache.mark_error(str(exc))
            logger.debug("GPS sentence parse failed: %s", exc)
            return

        if sentence.startswith(("$GPGGA", "$GNGGA")):
            self._handle_gga(msg)
        elif sentence.startswith(("$GPRMC", "$GNRMC")):
            self._handle_rmc(msg)

        if not self._working_state["fix"]:
            return
        if self._working_state["latitude"] is None or self._working_state["longitude"] is None:
            return

        state = {**self._working_state}
        state["recorded_at"] = datetime.now(timezone.utc)
        state["received_at"] = state["recorded_at"]

        latest = self.cache.snapshot()["latest"]
        moved_meters = None
        if latest["latitude"] is not None and latest["longitude"] is not None:
            moved_meters = geodesic(
                (float(latest["latitude"]), float(latest["longitude"])),
                (float(state["latitude"]), float(state["longitude"])),
            ).meters
            if moved_meters < self.settings.gps_min_move_meters:
                state["moved_meters"] = moved_meters
                self.cache.update_current(state)
                return

        state["moved_meters"] = moved_meters
        state["address"] = await self._maybe_reverse_geocode(state["latitude"], state["longitude"], latest)
        self.cache.update_current(state)
        persisted = await asyncio.to_thread(self._persist_fix, state)
        persisted["fix"] = True
        self.cache.update_latest(persisted)
        await run_broadcast(
            self.settings.device_id,
            {"type": "gps.fix.created", "payload": persisted},
        )

    def _handle_gga(self, msg: Any) -> None:
        gps_qual = int(getattr(msg, "gps_qual", 0) or 0)
        if gps_qual <= 0:
            self._working_state = _empty_state()
            self.cache.update_current(self._working_state)
            return

        timestamp = getattr(msg, "timestamp", None)
        satellites = getattr(msg, "num_sats", None)
        self._working_state.update(
            {
                "fix": True,
                "latitude": getattr(msg, "latitude", None),
                "longitude": getattr(msg, "longitude", None),
                "altitude_m": getattr(msg, "altitude", None),
                "satellites": str(satellites) if satellites is not None else None,
                "nmea_time": timestamp.isoformat() if timestamp else None,
            }
        )

    def _handle_rmc(self, msg: Any) -> None:
        if getattr(msg, "status", "") != "A":
            return

        timestamp = getattr(msg, "timestamp", None)
        speed_knots = getattr(msg, "spd_over_grnd", None)
        heading = getattr(msg, "true_course", None)
        self._working_state.update(
            {
                "speed_kmh": float(speed_knots) * 1.852 if speed_knots is not None else None,
                "heading_deg": float(heading) if heading is not None else None,
                "nmea_time": timestamp.isoformat() if timestamp else self._working_state.get("nmea_time"),
            }
        )

    async def _maybe_reverse_geocode(
        self,
        latitude: float | None,
        longitude: float | None,
        latest: dict[str, Any],
    ) -> str | None:
        if latitude is None or longitude is None:
            return latest.get("address")

        now = datetime.now(timezone.utc)
        should_lookup = (
            self._last_geocode_at is None
            or (now - self._last_geocode_at).total_seconds() >= self.settings.gps_reverse_geocode_interval_seconds
        )
        if not should_lookup:
            return latest.get("address")

        try:
            location = await asyncio.to_thread(
                self.geolocator.reverse,
                f"{latitude}, {longitude}",
                timeout=3,
                language="en",
            )
            if location and getattr(location, "address", None):
                self._last_geocode_at = now
                return location.address
        except GeocoderTimedOut:
            logger.warning("GPS reverse geocoding timed out")
        except Exception as exc:
            logger.warning("GPS reverse geocoding failed: %s", exc)

        return latest.get("address")

    def _persist_fix(self, state: dict[str, Any]) -> dict[str, Any]:
        db = SessionLocal()
        try:
            reading = create_gps_fix_sync(
                db,
                device_id=self.settings.device_id,
                station_name=self.settings.station_name,
                recorded_at=state["recorded_at"],
                latitude=float(state["latitude"]),
                longitude=float(state["longitude"]),
                altitude_m=state.get("altitude_m"),
                speed_kmh=state.get("speed_kmh"),
                heading_deg=state.get("heading_deg"),
                satellites=state.get("satellites"),
                nmea_time=state.get("nmea_time"),
                address=state.get("address"),
                moved_meters=state.get("moved_meters"),
            )
            return reading.model_dump(mode="python")
        except Exception as exc:
            self.cache.mark_error(str(exc))
            logger.exception("GPS fix persistence failed: %s", exc)
            raise
        finally:
            db.close()
