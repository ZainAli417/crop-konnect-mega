from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.models import Station, StationSettings
from app.schemas import (
    StationForecastSettingsResponse,
    SensorCadencePatch,
    SensorCadenceResponse,
    SensorToggleResponse,
    StationPollingSettingsResponse,
    StationSensorSchedulePatch,
    StationSensorScheduleResponse,
    StationRuntimeSettingsResponse,
    StationSensorsSettingsResponse,
    StationSettingsResponse,
    StationSettingsUpdateRequest,
)


ALLOWED_SENSOR_KEYS = ("wind_speed", "wind_direction", "soil", "rain", "uv")
DEFAULT_SENSOR_ORDER = ["uv", "wind_speed", "wind_direction", "soil", "rain"]
DEFAULT_SENSOR_READ_PLAN_JSON = "{}"
DEFAULT_SENSOR_PLAN_MODE = "reads_per_day"
DEFAULT_SENSOR_READS_PER_DAY = 24

MIN_POLL_INTERVAL_SECONDS = 1
MAX_POLL_INTERVAL_SECONDS = 604800
MIN_INTER_READ_DELAY_MS = 0
MAX_INTER_READ_DELAY_MS = 5000


def get_or_create_station(db: Session, device_id: str, station_name: str | None = None) -> Station:
    station = db.scalar(select(Station).where(Station.device_id == device_id))
    if station is not None:
        if station_name and station.name != station_name:
            station.name = station_name
        return station

    station = Station(device_id=device_id, name=station_name)
    db.add(station)
    db.flush()
    return station


def _normalize_sensor_key(value: str) -> str:
    key = value.strip().lower()
    if key in {"wind", "wind_sensor"}:
        return "wind"
    return "uv" if key == "solar" else key


def _normalize_sensor_order(order: list[str] | None, env: Settings) -> list[str]:
    raw = order if order is not None else env.sensor_read_sequence
    normalized: list[str] = []
    for item in raw:
        key = _normalize_sensor_key(item)
        if key == "wind":
            for wind_key in ("wind_speed", "wind_direction"):
                if wind_key not in normalized:
                    normalized.append(wind_key)
            continue
        if key in ALLOWED_SENSOR_KEYS and key not in normalized:
            normalized.append(key)
    return normalized or DEFAULT_SENSOR_ORDER.copy()


def _coerce_poll_interval(value: int) -> int:
    return max(MIN_POLL_INTERVAL_SECONDS, min(MAX_POLL_INTERVAL_SECONDS, int(value)))


def _coerce_inter_read_delay(value: int) -> int:
    return max(MIN_INTER_READ_DELAY_MS, min(MAX_INTER_READ_DELAY_MS, int(value)))


def _coerce_forecast_coordinate(value: float | int | str | None) -> float | None:
    if value is None:
        return None
    try:
        candidate = float(value)
    except (TypeError, ValueError):
        return None
    if candidate < -180.0 or candidate > 180.0:
        return None
    return candidate


def _sensor_schedule_keys() -> list[str]:
    return list(ALLOWED_SENSOR_KEYS)


def _sensor_schedule_key_from_storage(key: str) -> str | None:
    normalized = _normalize_sensor_key(key)
    if normalized == "wind":
        return "wind"
    if normalized in ALLOWED_SENSOR_KEYS:
        return normalized
    return None


def _default_sensor_read_plan(env: Settings) -> dict[str, dict[str, int | bool]]:
    return {
        key: {
            "mode": DEFAULT_SENSOR_PLAN_MODE,
            "reads_per_day": DEFAULT_SENSOR_READS_PER_DAY,
            "priority": None,
        }
        for key in _sensor_schedule_keys()
    }


def _parse_sensor_read_plan(value: str | None, env: Settings) -> dict[str, dict[str, int | bool]]:
    if not value:
        return {}
    try:
        payload = json.loads(value)
    except Exception:
        return {}
    if not isinstance(payload, dict):
        return {}

    plan: dict[str, dict[str, int | bool]] = {}
    for raw_key, raw_value in payload.items():
        key = _sensor_schedule_key_from_storage(str(raw_key))
        if key is None or not isinstance(raw_value, dict):
            continue
        reads_per_day = raw_value.get("reads_per_day")
        try:
            reads_value = max(0, int(reads_per_day))
        except Exception:
            reads_value = 0
        priority_raw = raw_value.get("priority")
        try:
            priority = int(priority_raw) if priority_raw is not None else None
        except Exception:
            priority = None
        plan[key] = {
            "mode": DEFAULT_SENSOR_PLAN_MODE,
            "reads_per_day": reads_value,
            "priority": priority,
        }
    return plan


def _normalize_sensor_read_plan_items(
    items: dict[str, SensorCadencePatch] | None,
    env: Settings,
) -> dict[str, dict[str, int | bool]] | None:
    if items is None:
        return None

    normalized: dict[str, dict[str, int | bool]] = {}
    for raw_key, patch in items.items():
        key = _sensor_schedule_key_from_storage(raw_key)
        if key is None:
            continue
        target_keys = ("wind_speed", "wind_direction") if key == "wind" else (key,)
        for target_key in target_keys:
            current = normalized.get(
                target_key,
                {
                    "mode": DEFAULT_SENSOR_PLAN_MODE,
                    "reads_per_day": DEFAULT_SENSOR_READS_PER_DAY,
                    "priority": None,
                },
            )
            if patch.mode is not None:
                mode = patch.mode.strip().lower()
                if mode == DEFAULT_SENSOR_PLAN_MODE:
                    current["mode"] = mode
            if patch.reads_per_day is not None:
                current["reads_per_day"] = max(0, int(patch.reads_per_day))
            if patch.priority is not None:
                current["priority"] = max(0, int(patch.priority))
            normalized[target_key] = current
    return normalized


def _sensor_read_plan_to_json(plan: dict[str, dict[str, int | bool]]) -> str:
    return json.dumps(plan, separators=(",", ":"), sort_keys=True)


def _reads_per_day_to_interval_seconds(reads_per_day: int | None) -> int | None:
    if reads_per_day is None or reads_per_day <= 0:
        return None
    interval = round(86400 / max(1, reads_per_day))
    return max(1, int(interval))


def _sensor_plan_response(
    row: StationSettings,
    env: Settings,
) -> dict[str, SensorCadenceResponse]:
    stored = _parse_sensor_read_plan(row.sensor_read_schedule_json, env)
    legacy_mode = not bool(stored)
    response: dict[str, SensorCadenceResponse] = {}
    enabled_map = {
        "wind_speed": bool(row.wind_speed_enabled),
        "wind_direction": bool(row.wind_direction_enabled),
        "soil": bool(row.soil_enabled),
        "rain": bool(row.rain_enabled),
        "uv": bool(row.uv_enabled),
    }
    for key in _sensor_schedule_keys():
        enabled = enabled_map[key]
        item = stored.get(key)
        if legacy_mode:
            response[key] = SensorCadenceResponse(
                enabled=enabled,
                mode=DEFAULT_SENSOR_PLAN_MODE,
                reads_per_day=None,
                interval_seconds=None,
                priority=None,
            )
            continue

        reads_per_day = None if item is None else int(item.get("reads_per_day", 0))
        response[key] = SensorCadenceResponse(
            enabled=enabled,
            mode=DEFAULT_SENSOR_PLAN_MODE,
            reads_per_day=reads_per_day,
            interval_seconds=_reads_per_day_to_interval_seconds(reads_per_day),
            priority=None if item is None else item.get("priority"),
        )
    return response


def _ensure_station_settings_row(db: Session, station: Station, env: Settings) -> StationSettings:
    row = db.scalar(select(StationSettings).where(StationSettings.station_id == station.id))
    if row is not None:
        return row

    row = StationSettings(
        station_id=station.id,
        wind_speed_enabled=False,
        wind_direction_enabled=False,
        soil_enabled=False,
        rain_enabled=False,
        uv_enabled=False,
        sensor_read_schedule_json=_sensor_read_plan_to_json(_default_sensor_read_plan(env)),
        forecast_latitude=None,
        forecast_longitude=None,
        poll_interval_seconds=_coerce_poll_interval(env.serial_poll_interval_seconds),
        inter_read_delay_ms=_coerce_inter_read_delay(env.sensor_inter_read_delay_ms),
        sensor_read_order=",".join(_normalize_sensor_order(None, env)),
    )
    db.add(row)
    db.flush()
    return row


def _to_response(station: Station, row: StationSettings, env: Settings) -> StationSettingsResponse:
    sensor_read_order = _normalize_sensor_order(row.sensor_read_order.split(","), env)
    return StationSettingsResponse(
        device_id=station.device_id,
        station_name=station.name,
        sensors=StationSensorsSettingsResponse(
            wind_speed=SensorToggleResponse(enabled=bool(row.wind_speed_enabled)),
            wind_direction=SensorToggleResponse(enabled=bool(row.wind_direction_enabled)),
            soil=SensorToggleResponse(enabled=bool(row.soil_enabled)),
            rain=SensorToggleResponse(enabled=bool(row.rain_enabled)),
            uv=SensorToggleResponse(enabled=bool(row.uv_enabled)),
        ),
        polling=StationPollingSettingsResponse(
            poll_interval_seconds=_coerce_poll_interval(row.poll_interval_seconds),
            inter_read_delay_ms=_coerce_inter_read_delay(row.inter_read_delay_ms),
            sensor_read_order=sensor_read_order,
            sensor_schedule=StationSensorScheduleResponse(items=_sensor_plan_response(row, env)),
        ),
        runtime=StationRuntimeSettingsResponse(
            forecast=StationForecastSettingsResponse(
                latitude=row.forecast_latitude,
                longitude=row.forecast_longitude,
            ),
        ),
        updated_at=row.updated_at,
    )


def fetch_station_settings(
    db: Session,
    device_id: str,
    station_name: str | None = None,
    env: Settings | None = None,
) -> StationSettingsResponse:
    env_settings = env or get_settings()
    station = get_or_create_station(db, device_id=device_id, station_name=station_name)
    row = _ensure_station_settings_row(db, station, env_settings)
    db.commit()
    db.refresh(station)
    db.refresh(row)
    return _to_response(station, row, env_settings)


def patch_station_settings(
    db: Session,
    device_id: str,
    payload: StationSettingsUpdateRequest,
    station_name: str | None = None,
    env: Settings | None = None,
) -> StationSettingsResponse:
    env_settings = env or get_settings()
    station = get_or_create_station(db, device_id=device_id, station_name=station_name)
    row = _ensure_station_settings_row(db, station, env_settings)

    if payload.sensors is not None:
        if payload.sensors.wind_speed is not None and payload.sensors.wind_speed.enabled is not None:
            row.wind_speed_enabled = payload.sensors.wind_speed.enabled
            row.wind_direction_enabled = payload.sensors.wind_speed.enabled
        if payload.sensors.wind_direction is not None and payload.sensors.wind_direction.enabled is not None:
            row.wind_direction_enabled = payload.sensors.wind_direction.enabled
            row.wind_speed_enabled = payload.sensors.wind_direction.enabled
        if payload.sensors.soil is not None and payload.sensors.soil.enabled is not None:
            row.soil_enabled = payload.sensors.soil.enabled
        if payload.sensors.rain is not None and payload.sensors.rain.enabled is not None:
            row.rain_enabled = payload.sensors.rain.enabled
        if payload.sensors.uv is not None and payload.sensors.uv.enabled is not None:
            row.uv_enabled = payload.sensors.uv.enabled

    if payload.polling is not None:
        if payload.polling.poll_interval_seconds is not None:
            row.poll_interval_seconds = _coerce_poll_interval(payload.polling.poll_interval_seconds)
        if payload.polling.inter_read_delay_ms is not None:
            row.inter_read_delay_ms = _coerce_inter_read_delay(payload.polling.inter_read_delay_ms)
        if payload.polling.sensor_read_order is not None:
            normalized_order = _normalize_sensor_order(payload.polling.sensor_read_order, env_settings)
            row.sensor_read_order = ",".join(normalized_order)
        if payload.polling.sensor_schedule is not None and payload.polling.sensor_schedule.items is not None:
            normalized_plan = _normalize_sensor_read_plan_items(payload.polling.sensor_schedule.items, env_settings)
            if normalized_plan is not None:
                merged_plan = _default_sensor_read_plan(env_settings)
                merged_plan.update(_parse_sensor_read_plan(row.sensor_read_schedule_json, env_settings))
                merged_plan.update(normalized_plan)
                row.sensor_read_schedule_json = _sensor_read_plan_to_json(merged_plan)
    if payload.runtime is not None:
        if payload.runtime.forecast is not None:
            forecast = payload.runtime.forecast
            if forecast.latitude is not None:
                row.forecast_latitude = _coerce_forecast_coordinate(forecast.latitude)
            if forecast.longitude is not None:
                row.forecast_longitude = _coerce_forecast_coordinate(forecast.longitude)

    db.commit()
    db.refresh(station)
    db.refresh(row)
    return _to_response(station, row, env_settings)


def ensure_station_settings(
    db: Session,
    station: Station,
    env: Settings | None = None,
) -> StationSettings:
    env_settings = env or get_settings()
    row = _ensure_station_settings_row(db, station, env_settings)
    return row


def get_enabled_sensor_groups(db: Session, device_id: str) -> dict[str, bool] | None:
    station = db.scalar(select(Station).where(Station.device_id == device_id))
    if station is None:
        return None

    row = db.scalar(select(StationSettings).where(StationSettings.station_id == station.id))
    if row is None:
        return {"wind": False, "soil": False, "rain": False, "uv": False}

    return {
        "wind": bool(row.wind_speed_enabled or row.wind_direction_enabled),
        "soil": bool(row.soil_enabled),
        "rain": bool(row.rain_enabled),
        "uv": bool(row.uv_enabled),
    }


@dataclass(frozen=True)
class StationRuntimeSettings:
    poll_interval_seconds: int
    inter_read_delay_ms: int
    sensor_read_sequence: list[str]
    enabled: dict[str, bool]
    sensor_read_plan: dict[str, dict[str, int | bool]]
    forecast_latitude: float | None = None
    forecast_longitude: float | None = None
    updated_at: datetime | None = None


def load_runtime_settings(
    db: Session,
    device_id: str,
    station_name: str | None = None,
    env: Settings | None = None,
) -> StationRuntimeSettings:
    env_settings = env or get_settings()
    station = get_or_create_station(db, device_id=device_id, station_name=station_name)
    row = _ensure_station_settings_row(db, station, env_settings)
    if db.new or db.dirty or db.deleted:
        db.commit()

    order_api = _normalize_sensor_order(row.sensor_read_order.split(","), env_settings)
    order_internal = ["solar" if key == "uv" else key for key in order_api]
    raw_sensor_read_plan = _parse_sensor_read_plan(row.sensor_read_schedule_json, env_settings)
    sensor_read_plan = {
        ("solar" if key == "uv" else key): value
        for key, value in raw_sensor_read_plan.items()
    }
    enabled = {
        "wind_speed": bool(row.wind_speed_enabled),
        "wind_direction": bool(row.wind_direction_enabled),
        "soil": bool(row.soil_enabled),
        "rain": bool(row.rain_enabled),
        "solar": bool(row.uv_enabled),
    }

    return StationRuntimeSettings(
        poll_interval_seconds=_coerce_poll_interval(row.poll_interval_seconds),
        inter_read_delay_ms=_coerce_inter_read_delay(row.inter_read_delay_ms),
        sensor_read_sequence=order_internal,
        enabled=enabled,
        sensor_read_plan=sensor_read_plan,
        forecast_latitude=row.forecast_latitude,
        forecast_longitude=row.forecast_longitude,
        updated_at=row.updated_at,
    )

