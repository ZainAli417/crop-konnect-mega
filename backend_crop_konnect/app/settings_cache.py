"""Shared, TTL-cached access to station runtime settings.

Why this exists
---------------
Both pollers used to call ``load_runtime_settings`` on a fresh ``Session`` every
``SETTINGS_REFRESH_INTERVAL_SECONDS`` (default 1s) for the whole duration of
every sleep. Each call was a connection checkout (plus a ``SELECT 1`` from
``pool_pre_ping``), a station SELECT, a settings SELECT and sometimes a COMMIT.
With two pollers that is roughly six to eight round trips per second, forever,
against a remote Supabase pooler — for settings that change when a human taps a
toggle.

This module collapses that to one cheap change-detection query per TTL, shared
by every caller:

* a full load populates the cache;
* subsequent refreshes read only ``station_settings.updated_at`` and reuse the
  cached object unless it moved;
* failures serve the last known-good value instead of flapping the station into
  its "everything disabled" fallback.
"""

from __future__ import annotations

import logging
import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select

from app.config import Settings, get_settings
from app.db import SessionLocal
from app.models import Station, StationSettings
from app.station_settings import StationRuntimeSettings, load_runtime_settings


logger = logging.getLogger(__name__)


@dataclass
class _CacheEntry:
    runtime: StationRuntimeSettings
    loaded_at: float
    checked_at: float
    updated_at: datetime | None


class StationSettingsCache:
    """Process-wide cache of one station's runtime settings.

    Thread-safe: the sensor pollers call this from worker threads.
    """

    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or get_settings()
        self._lock = threading.RLock()
        self._entry: _CacheEntry | None = None
        self._station_id: int | None = None
        self.last_error: str | None = None
        self.full_loads = 0
        self.change_checks = 0
        self.cache_hits = 0

    # -- internals --------------------------------------------------------

    def _ttl_seconds(self) -> float:
        return max(1.0, float(self.settings.settings_cache_ttl_seconds))

    def _now(self) -> float:
        return datetime.now(timezone.utc).timestamp()

    def _full_load(self) -> StationRuntimeSettings | None:
        """Load everything and remember the station id for cheap checks later."""
        db = SessionLocal()
        try:
            runtime = load_runtime_settings(
                db,
                device_id=self.settings.device_id,
                station_name=self.settings.station_name,
                env=self.settings,
            )
            if self._station_id is None:
                self._station_id = db.scalar(
                    select(Station.id).where(Station.device_id == self.settings.device_id)
                )
            self.full_loads += 1
            self.last_error = None
            return runtime
        except Exception as exc:
            self.last_error = str(exc)
            logger.warning("Station settings load failed: %s", exc)
            return None
        finally:
            db.close()

    def _peek_updated_at(self) -> tuple[bool, datetime | None]:
        """Read only ``updated_at``. Returns (query_ok, value)."""
        station_id = self._station_id
        if station_id is None:
            return False, None
        db = SessionLocal()
        try:
            value = db.scalar(
                select(StationSettings.updated_at).where(
                    StationSettings.station_id == station_id
                )
            )
            self.change_checks += 1
            self.last_error = None
            return True, value
        except Exception as exc:
            self.last_error = str(exc)
            logger.debug("Station settings change-check failed: %s", exc)
            return False, None
        finally:
            db.close()

    # -- public API -------------------------------------------------------

    def get(self, *, force: bool = False) -> StationRuntimeSettings | None:
        """Current settings, refreshing at most once per TTL.

        Returns None only when nothing has ever loaded successfully — callers
        should then keep their previous behaviour rather than assuming "off".
        """
        with self._lock:
            now = self._now()
            entry = self._entry

            if entry is not None and not force and (now - entry.checked_at) < self._ttl_seconds():
                self.cache_hits += 1
                return entry.runtime

            if entry is None or force:
                runtime = self._full_load()
                if runtime is None:
                    return None if entry is None else entry.runtime
                self._entry = _CacheEntry(
                    runtime=runtime,
                    loaded_at=now,
                    checked_at=now,
                    updated_at=runtime.updated_at,
                )
                return runtime

            # TTL expired: one cheap column read decides whether to reload.
            ok, updated_at = self._peek_updated_at()
            if not ok:
                # Could not check — keep serving the last good value and try
                # again next TTL. Never flap the station off because of a
                # transient network blip.
                entry.checked_at = now
                return entry.runtime

            if updated_at == entry.updated_at:
                entry.checked_at = now
                self.cache_hits += 1
                return entry.runtime

            runtime = self._full_load()
            if runtime is None:
                entry.checked_at = now
                return entry.runtime

            self._entry = _CacheEntry(
                runtime=runtime,
                loaded_at=now,
                checked_at=now,
                updated_at=runtime.updated_at,
            )
            logger.info(
                "Station settings changed for %s; reloaded (updated_at=%s)",
                self.settings.device_id,
                runtime.updated_at,
            )
            return runtime

    def invalidate(self) -> None:
        """Force the next :meth:`get` to reload. Call after a settings PATCH."""
        with self._lock:
            if self._entry is not None:
                self._entry.checked_at = 0.0

    @property
    def station_id(self) -> int | None:
        return self._station_id

    def status(self) -> dict[str, Any]:
        with self._lock:
            entry = self._entry
            return {
                "ttl_seconds": self._ttl_seconds(),
                "station_id": self._station_id,
                "loaded": entry is not None,
                "updated_at": None if entry is None else entry.updated_at,
                "full_loads": self.full_loads,
                "change_checks": self.change_checks,
                "cache_hits": self.cache_hits,
                "last_error": self.last_error,
            }


# One cache per process, shared by the sensor and solar pollers.
_cache: StationSettingsCache | None = None
_cache_lock = threading.Lock()


def get_settings_cache(settings: Settings | None = None) -> StationSettingsCache:
    global _cache
    with _cache_lock:
        if _cache is None:
            _cache = StationSettingsCache(settings)
        return _cache
