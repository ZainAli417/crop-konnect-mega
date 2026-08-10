from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from sqlalchemy import desc, func, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.models import (
    IrrigationActionLog,
    IrrigationAdvisory,
    IrrigationProfile,
    LatestReading,
    SensorReading,
    Station,
    StationSettings,
)
from app.schemas import (
    IrrigationActionRequest,
    IrrigationActionResponse,
    IrrigationAdvisoryResponse,
    IrrigationCropOptionResponse,
    IrrigationPresetListResponse,
    IrrigationPresetStageResponse,
    IrrigationProfileResponse,
    IrrigationProfileUpdateRequest,
)
from app.weather_forecast import fetch_weather_forecast
from app.station_settings import load_runtime_settings


RULE_VERSION = "irrigation-v1"
DECISION_START = "start_irrigation"
DECISION_DELAY = "delay_irrigation"
DECISION_NONE = "no_irrigation_needed"
DECISION_HOLD = "hold_decision"
ALLOWED_ACTIONS = {
    "started_irrigation",
    "delayed",
    "ignored",
    "already_irrigated",
    "dismissed",
}

IRRIGATION_PRESETS: dict[str, dict[str, dict[str, Any]]] = {
    "Rice": {
        "Seedling": {
            "moisture_lower_target": 45,
            "moisture_upper_target": 75,
            "effective_rain_mm": 2,
            "rain_window_hours": 6,
            "high_temp_c": 34,
            "high_solar_wm2": 700,
            "high_wind_ms": 6,
            "stale_after_minutes": 10,
        },
        "Vegetative": {
            "moisture_lower_target": 35,
            "moisture_upper_target": 65,
            "effective_rain_mm": 2,
            "rain_window_hours": 6,
            "high_temp_c": 35,
            "high_solar_wm2": 700,
            "high_wind_ms": 6,
            "stale_after_minutes": 10,
        },
        "Flowering": {
            "moisture_lower_target": 40,
            "moisture_upper_target": 70,
            "effective_rain_mm": 2,
            "rain_window_hours": 6,
            "high_temp_c": 34,
            "high_solar_wm2": 650,
            "high_wind_ms": 5,
            "stale_after_minutes": 10,
        },
        "Maturity": {
            "moisture_lower_target": 30,
            "moisture_upper_target": 60,
            "effective_rain_mm": 3,
            "rain_window_hours": 8,
            "high_temp_c": 36,
            "high_solar_wm2": 750,
            "high_wind_ms": 7,
            "stale_after_minutes": 15,
        },
    },
    "Wheat": {
        "Tillering": {
            "moisture_lower_target": 30,
            "moisture_upper_target": 55,
            "effective_rain_mm": 2,
            "rain_window_hours": 8,
            "high_temp_c": 30,
            "high_solar_wm2": 650,
            "high_wind_ms": 6,
            "stale_after_minutes": 15,
        },
        "Booting": {
            "moisture_lower_target": 35,
            "moisture_upper_target": 60,
            "effective_rain_mm": 2,
            "rain_window_hours": 8,
            "high_temp_c": 30,
            "high_solar_wm2": 650,
            "high_wind_ms": 6,
            "stale_after_minutes": 15,
        },
        "Flowering": {
            "moisture_lower_target": 38,
            "moisture_upper_target": 62,
            "effective_rain_mm": 2,
            "rain_window_hours": 8,
            "high_temp_c": 29,
            "high_solar_wm2": 650,
            "high_wind_ms": 5,
            "stale_after_minutes": 15,
        },
        "Grain Filling": {
            "moisture_lower_target": 32,
            "moisture_upper_target": 58,
            "effective_rain_mm": 3,
            "rain_window_hours": 8,
            "high_temp_c": 32,
            "high_solar_wm2": 700,
            "high_wind_ms": 6,
            "stale_after_minutes": 15,
        },
    },
    "Maize": {
        "Vegetative": {
            "moisture_lower_target": 32,
            "moisture_upper_target": 60,
            "effective_rain_mm": 2,
            "rain_window_hours": 6,
            "high_temp_c": 35,
            "high_solar_wm2": 750,
            "high_wind_ms": 6,
            "stale_after_minutes": 10,
        },
        "Tasseling": {
            "moisture_lower_target": 38,
            "moisture_upper_target": 65,
            "effective_rain_mm": 2,
            "rain_window_hours": 6,
            "high_temp_c": 34,
            "high_solar_wm2": 700,
            "high_wind_ms": 5,
            "stale_after_minutes": 10,
        },
        "Silking": {
            "moisture_lower_target": 40,
            "moisture_upper_target": 68,
            "effective_rain_mm": 2,
            "rain_window_hours": 6,
            "high_temp_c": 34,
            "high_solar_wm2": 700,
            "high_wind_ms": 5,
            "stale_after_minutes": 10,
        },
        "Grain Filling": {
            "moisture_lower_target": 34,
            "moisture_upper_target": 62,
            "effective_rain_mm": 3,
            "rain_window_hours": 8,
            "high_temp_c": 36,
            "high_solar_wm2": 750,
            "high_wind_ms": 6,
            "stale_after_minutes": 15,
        },
    },
    "Cotton": {
        "Vegetative": {
            "moisture_lower_target": 28,
            "moisture_upper_target": 55,
            "effective_rain_mm": 2,
            "rain_window_hours": 8,
            "high_temp_c": 38,
            "high_solar_wm2": 800,
            "high_wind_ms": 7,
            "stale_after_minutes": 15,
        },
        "Flowering": {
            "moisture_lower_target": 34,
            "moisture_upper_target": 60,
            "effective_rain_mm": 2,
            "rain_window_hours": 8,
            "high_temp_c": 36,
            "high_solar_wm2": 750,
            "high_wind_ms": 6,
            "stale_after_minutes": 15,
        },
        "Boll Development": {
            "moisture_lower_target": 32,
            "moisture_upper_target": 58,
            "effective_rain_mm": 3,
            "rain_window_hours": 8,
            "high_temp_c": 37,
            "high_solar_wm2": 780,
            "high_wind_ms": 6,
            "stale_after_minutes": 15,
        },
    },
    "Vegetables": {
        "Seedling": {
            "moisture_lower_target": 40,
            "moisture_upper_target": 70,
            "effective_rain_mm": 2,
            "rain_window_hours": 4,
            "high_temp_c": 32,
            "high_solar_wm2": 650,
            "high_wind_ms": 5,
            "stale_after_minutes": 10,
        },
        "Vegetative": {
            "moisture_lower_target": 35,
            "moisture_upper_target": 65,
            "effective_rain_mm": 2,
            "rain_window_hours": 4,
            "high_temp_c": 34,
            "high_solar_wm2": 700,
            "high_wind_ms": 5,
            "stale_after_minutes": 10,
        },
        "Flowering": {
            "moisture_lower_target": 38,
            "moisture_upper_target": 68,
            "effective_rain_mm": 2,
            "rain_window_hours": 4,
            "high_temp_c": 33,
            "high_solar_wm2": 680,
            "high_wind_ms": 5,
            "stale_after_minutes": 10,
        },
        "Fruiting": {
            "moisture_lower_target": 40,
            "moisture_upper_target": 70,
            "effective_rain_mm": 2,
            "rain_window_hours": 4,
            "high_temp_c": 33,
            "high_solar_wm2": 680,
            "high_wind_ms": 5,
            "stale_after_minutes": 10,
        },
    },
}

CROP_MOISTURE_RANGES_PATH = Path(__file__).resolve().parent / "data" / "crop_moisture_ranges.json"
DEFAULT_PRESET_THRESHOLDS = {
    "effective_rain_mm": 2,
    "rain_window_hours": 6,
    "high_temp_c": 35,
    "high_solar_wm2": 700,
    "high_wind_ms": 6,
    "stale_after_minutes": 15,
}
FALLBACK_IRRIGATION_PRESETS = IRRIGATION_PRESETS


def _load_irrigation_presets() -> dict[str, dict[str, dict[str, Any]]]:
    try:
        raw_data = json.loads(CROP_MOISTURE_RANGES_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return FALLBACK_IRRIGATION_PRESETS

    if not isinstance(raw_data, dict):
        return FALLBACK_IRRIGATION_PRESETS

    presets: dict[str, dict[str, dict[str, Any]]] = {}
    for key, item in raw_data.items():
        if not isinstance(item, dict):
            continue
        crop = str(item.get("crop") or key).strip()
        stages = item.get("stages")
        if not crop or not isinstance(stages, list):
            continue

        crop_stages: dict[str, dict[str, Any]] = {}
        for stage_item in stages:
            if not isinstance(stage_item, dict):
                continue
            stage = str(stage_item.get("stage") or "").strip()
            lower = stage_item.get("lower_moisture")
            upper = stage_item.get("upper_moisture")
            if not stage or not isinstance(lower, (int, float)) or not isinstance(upper, (int, float)):
                continue
            if lower < 0 or upper > 100 or lower >= upper:
                continue

            crop_stages[stage] = {
                "moisture_lower_target": float(lower),
                "moisture_upper_target": float(upper),
                **DEFAULT_PRESET_THRESHOLDS,
            }

        if crop_stages:
            presets[crop] = crop_stages

    return presets or FALLBACK_IRRIGATION_PRESETS


IRRIGATION_PRESETS = _load_irrigation_presets()


def _normalize_option(value: str) -> str:
    normalized = value.strip().lower()
    for separator in ("-", "_", "/", "&"):
        normalized = normalized.replace(separator, " ")
    return " ".join(normalized.split())


def _canonical_crop(value: str) -> str | None:
    normalized = _normalize_option(value)
    for crop in IRRIGATION_PRESETS:
        if _normalize_option(crop) == normalized:
            return crop
    return None


def _canonical_stage(crop: str, value: str) -> str | None:
    normalized = _normalize_option(value)
    for stage in IRRIGATION_PRESETS[crop]:
        if _normalize_option(stage) == normalized:
            return stage
    return None


def list_irrigation_presets() -> IrrigationPresetListResponse:
    return IrrigationPresetListResponse(
        items=[
            IrrigationCropOptionResponse(
                crop=crop,
                stages=[
                    IrrigationPresetStageResponse(stage=stage, **thresholds)
                    for stage, thresholds in stages.items()
                ],
            )
            for crop, stages in IRRIGATION_PRESETS.items()
        ],
    )


def _apply_crop_stage_preset(profile: IrrigationProfile, crop_value: str, stage_value: str) -> None:
    crop = _canonical_crop(crop_value)
    if crop is None:
        supported = ", ".join(IRRIGATION_PRESETS.keys())
        raise ValueError(f"Unsupported crop '{crop_value}'. Supported crops: {supported}")

    stage = _canonical_stage(crop, stage_value)
    if stage is None:
        supported = ", ".join(IRRIGATION_PRESETS[crop].keys())
        raise ValueError(f"Unsupported stage '{stage_value}' for {crop}. Supported stages: {supported}")

    preset = IRRIGATION_PRESETS[crop][stage]
    profile.crop = crop
    profile.crop_stage = stage
    profile.soil_type = "System Preset"
    profile.irrigation_method = "System Managed"
    for field_name, value in preset.items():
        setattr(profile, field_name, value)


def _as_utc(value: datetime | None) -> datetime:
    if value is None:
        return datetime.fromtimestamp(0, tz=timezone.utc)
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _json_dump(value: dict[str, Any]) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True, default=str)


def _json_load(value: str | None) -> dict[str, Any]:
    if not value:
        return {}
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


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


def ensure_irrigation_profile(
    db: Session,
    station: Station,
    *,
    field_name: str | None = None,
) -> IrrigationProfile:
    profile = db.scalar(select(IrrigationProfile).where(IrrigationProfile.station_id == station.id))
    if profile is not None:
        if field_name and profile.field_name != field_name:
            profile.field_name = field_name
        return profile

    profile = IrrigationProfile(
        station_id=station.id,
        field_name=field_name or station.name,
    )
    db.add(profile)
    db.flush()
    return profile


def profile_to_response(station: Station, profile: IrrigationProfile) -> IrrigationProfileResponse:
    return IrrigationProfileResponse(
        id=profile.id,
        device_id=station.device_id,
        station_name=station.name,
        field_name=profile.field_name,
        crop=profile.crop,
        crop_stage=profile.crop_stage,
        soil_type=profile.soil_type,
        irrigation_method=profile.irrigation_method,
        smart_irrigation_enabled=bool(profile.smart_irrigation_enabled),
        moisture_lower_target=profile.moisture_lower_target,
        moisture_upper_target=profile.moisture_upper_target,
        effective_rain_mm=profile.effective_rain_mm,
        rain_window_hours=profile.rain_window_hours,
        high_temp_c=profile.high_temp_c,
        high_solar_wm2=profile.high_solar_wm2,
        high_wind_ms=profile.high_wind_ms,
        stale_after_minutes=profile.stale_after_minutes,
        created_at=profile.created_at,
        updated_at=profile.updated_at,
    )


def fetch_irrigation_profile(db: Session, device_id: str) -> IrrigationProfileResponse:
    station = get_or_create_station(db, device_id)
    profile = ensure_irrigation_profile(db, station)
    db.commit()
    db.refresh(station)
    db.refresh(profile)
    return profile_to_response(station, profile)


def patch_irrigation_profile(
    db: Session,
    device_id: str,
    payload: IrrigationProfileUpdateRequest,
) -> IrrigationProfileResponse:
    station = get_or_create_station(db, device_id)
    profile = ensure_irrigation_profile(db, station)
    values = payload.model_dump(exclude_unset=True)

    if "smart_irrigation_enabled" in values:
        profile.smart_irrigation_enabled = bool(values["smart_irrigation_enabled"])
    elif "crop" in values or "crop_stage" in values:
        profile.smart_irrigation_enabled = True

    crop = values.get("crop", profile.crop)
    crop_stage = values.get("crop_stage", profile.crop_stage)
    should_apply_preset = (
        "crop" in values
        or "crop_stage" in values
        or values.get("smart_irrigation_enabled") is True
    )
    if should_apply_preset:
        _apply_crop_stage_preset(profile, str(crop), str(crop_stage))

    if "field_name" in values:
        profile.field_name = values["field_name"] or profile.field_name
    if "soil_type" in values and values["soil_type"] is not None:
        profile.soil_type = str(values["soil_type"])
    if "irrigation_method" in values and values["irrigation_method"] is not None:
        profile.irrigation_method = str(values["irrigation_method"])
    if "moisture_lower_target" in values and values["moisture_lower_target"] is not None:
        profile.moisture_lower_target = float(values["moisture_lower_target"])
    if "moisture_upper_target" in values and values["moisture_upper_target"] is not None:
        profile.moisture_upper_target = float(values["moisture_upper_target"])
    if "effective_rain_mm" in values and values["effective_rain_mm"] is not None:
        profile.effective_rain_mm = float(values["effective_rain_mm"])
    if "rain_window_hours" in values and values["rain_window_hours"] is not None:
        profile.rain_window_hours = int(values["rain_window_hours"])
    if "high_temp_c" in values and values["high_temp_c"] is not None:
        profile.high_temp_c = float(values["high_temp_c"])
    if "high_solar_wm2" in values and values["high_solar_wm2"] is not None:
        profile.high_solar_wm2 = float(values["high_solar_wm2"])
    if "high_wind_ms" in values and values["high_wind_ms"] is not None:
        profile.high_wind_ms = float(values["high_wind_ms"])
    if "stale_after_minutes" in values and values["stale_after_minutes"] is not None:
        profile.stale_after_minutes = int(values["stale_after_minutes"])

    db.commit()
    db.refresh(station)
    db.refresh(profile)
    return profile_to_response(station, profile)


def _reading_snapshot(station: Station, reading: SensorReading) -> dict[str, Any]:
    return {
        "device_id": station.device_id,
        "station_name": station.name,
        "reading_id": reading.id,
        "recorded_at": reading.recorded_at.isoformat(),
        "received_at": reading.received_at.isoformat() if reading.received_at else None,
        "values": {
            "moist": {"value": reading.soil_moisture, "unit": "%"},
            "rain": {"value": reading.rainfall, "unit": "mm"},
            "solar": {"value": reading.solar_radiation, "unit": "W/m2"},
            "ws": {"value": reading.wind_speed, "unit": "m/s"},
            "temp": {"value": reading.soil_temperature, "unit": "C"},
        },
    }


def _profile_snapshot(profile: IrrigationProfile) -> dict[str, Any]:
    return {
        "profile_id": profile.id,
        "field_name": profile.field_name,
        "crop": profile.crop,
        "crop_stage": profile.crop_stage,
        "soil_type": profile.soil_type,
        "irrigation_method": profile.irrigation_method,
        "smart_irrigation_enabled": bool(profile.smart_irrigation_enabled),
        "thresholds": {
            "moisture_lower_target": profile.moisture_lower_target,
            "moisture_upper_target": profile.moisture_upper_target,
            "effective_rain_mm": profile.effective_rain_mm,
            "rain_window_hours": profile.rain_window_hours,
            "high_temp_c": profile.high_temp_c,
            "high_solar_wm2": profile.high_solar_wm2,
            "high_wind_ms": profile.high_wind_ms,
            "stale_after_minutes": profile.stale_after_minutes,
        },
        "updated_at": profile.updated_at.isoformat() if profile.updated_at else None,
    }


def _classify_moisture(value: float | None, profile: IrrigationProfile) -> str:
    if value is None:
        return "unknown"
    if value < profile.moisture_lower_target:
        return "dry"
    if value <= profile.moisture_upper_target:
        return "acceptable"
    return "wet"


def _classify_weather_demand(reading: SensorReading, profile: IrrigationProfile) -> tuple[str, int, dict[str, str]]:
    checks = {
        "solar": "unknown",
        "wind": "unknown",
        "temperature": "unknown",
    }
    score = 0
    known = 0

    if reading.solar_radiation is not None:
        known += 1
        if reading.solar_radiation >= profile.high_solar_wm2:
            score += 1
            checks["solar"] = "high"
        else:
            checks["solar"] = "normal"

    if reading.wind_speed is not None:
        known += 1
        if reading.wind_speed >= profile.high_wind_ms:
            score += 1
            checks["wind"] = "high"
        else:
            checks["wind"] = "normal"

    if reading.soil_temperature is not None:
        known += 1
        if reading.soil_temperature >= profile.high_temp_c:
            score += 1
            checks["temperature"] = "high"
        else:
            checks["temperature"] = "normal"

    if known == 0:
        return "unknown", score, checks
    if score >= 2:
        return "high", score, checks
    if score == 1:
        return "medium", score, checks
    return "low", score, checks


def _recent_rain_context(db: Session, station_id: int, reading: SensorReading, profile: IrrigationProfile) -> dict[str, Any]:
    recorded_at = _as_utc(reading.recorded_at)
    since = recorded_at - timedelta(hours=profile.rain_window_hours)
    rows = db.scalars(
        select(SensorReading.rainfall)
        .where(
            SensorReading.station_id == station_id,
            SensorReading.recorded_at >= since,
            SensorReading.recorded_at <= reading.recorded_at,
            SensorReading.rainfall.is_not(None),
        )
        .order_by(SensorReading.recorded_at.asc())
    ).all()

    values = [max(0.0, float(value)) for value in rows if value is not None]
    total = round(sum(values), 3)
    latest = max(0.0, float(reading.rainfall)) if reading.rainfall is not None else None
    effective = total >= profile.effective_rain_mm or (
        latest is not None and latest >= profile.effective_rain_mm
    )

    return {
        "status": "effective_recent_rain" if effective else "none_recent",
        "window_hours": profile.rain_window_hours,
        "effective_rain_mm": profile.effective_rain_mm,
        "total_mm": total,
        "latest_mm": latest,
        "sample_count": len(values),
    }


def _freshness_context(reading: SensorReading, profile: IrrigationProfile) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    recorded_at = _as_utc(reading.recorded_at)
    age_minutes = max(0.0, (now - recorded_at).total_seconds() / 60)
    ingest_delay_minutes = None
    if reading.received_at is not None:
        ingest_delay_minutes = max(
            0.0,
            (_as_utc(reading.received_at) - recorded_at).total_seconds() / 60,
        )

    status = "fresh" if age_minutes <= profile.stale_after_minutes else "stale"
    return {
        "status": status,
        "age_minutes": round(age_minutes, 2),
        "ingest_delay_minutes": None if ingest_delay_minutes is None else round(ingest_delay_minutes, 2),
        "stale_after_minutes": profile.stale_after_minutes,
    }


def _forecast_context(db: Session, station: Station, profile: IrrigationProfile) -> dict[str, Any]:
    station_settings = db.scalar(select(StationSettings).where(StationSettings.station_id == station.id))
    forecast = fetch_weather_forecast(
        get_settings(),
        latitude=station_settings.forecast_latitude if station_settings else None,
        longitude=station_settings.forecast_longitude if station_settings else None,
    )
    if forecast is None:
        return {
            "status": "unavailable",
            "reason": "No forecast source configured or forecast request failed.",
        }

    summary = forecast.get("summary") or {}
    classification = forecast.get("classification") or {}

    forecast_rain_total = summary.get("rain_total_mm")
    forecast_rain_expected = bool(summary.get("rain_expected"))
    forecast_temperature_max = summary.get("temperature_max_c")
    forecast_wind_max = summary.get("wind_max_ms")
    forecast_humidity_min = summary.get("humidity_min_pct")

    hot_expected = isinstance(forecast_temperature_max, (int, float)) and forecast_temperature_max >= profile.high_temp_c
    windy_expected = isinstance(forecast_wind_max, (int, float)) and forecast_wind_max >= profile.high_wind_ms

    if forecast_rain_expected:
        status = "rain_expected"
    elif hot_expected or windy_expected:
        status = "drying_expected"
    else:
        status = "clear"

    return {
        "status": status,
        "provider": forecast.get("provider"),
        "timezone": forecast.get("timezone"),
        "generated_at": forecast.get("generated_at"),
        "horizon_hours": forecast.get("horizon_hours"),
        "summary": summary,
        "classification": classification,
        "signals": {
            "rain_expected": forecast_rain_expected,
            "hot_expected": hot_expected,
            "windy_expected": windy_expected,
            "temperature_max_c": forecast_temperature_max,
            "wind_max_ms": forecast_wind_max,
            "humidity_min_pct": forecast_humidity_min,
            "rain_total_mm": forecast_rain_total,
        },
    }


def _evaluate_irrigation(
    db: Session,
    station: Station,
    reading: SensorReading,
    profile: IrrigationProfile,
) -> dict[str, Any]:
    moisture_status = _classify_moisture(reading.soil_moisture, profile)
    rain = _recent_rain_context(db, station.id, reading, profile)
    weather_demand, weather_score, weather_checks = _classify_weather_demand(reading, profile)
    freshness = _freshness_context(reading, profile)
    forecast = _forecast_context(db, station, profile)

    factors = {
        "soil_moisture": {
            "status": moisture_status,
            "value": reading.soil_moisture,
            "unit": "%",
            "lower_target": profile.moisture_lower_target,
            "upper_target": profile.moisture_upper_target,
        },
        "rain": rain,
        "weather_demand": {
            "status": weather_demand,
            "score": weather_score,
            "checks": weather_checks,
            "thresholds": {
                "high_solar_wm2": profile.high_solar_wm2,
                "high_wind_ms": profile.high_wind_ms,
                "high_temp_c": profile.high_temp_c,
            },
        },
        "freshness": freshness,
        "forecast": forecast,
    }

    if freshness["status"] != "fresh":
        return {
            "decision": DECISION_HOLD,
            "urgency": "none",
            "data_status": "stale",
            "title": "Decision held",
            "message": "Sensor data is delayed and should be refreshed before irrigation advice is trusted.",
            "reason": "The latest reading is older than the allowed freshness window.",
            "condition_summary": "stale_data",
            "factors": factors,
        }

    if moisture_status == "unknown":
        return {
            "decision": DECISION_HOLD,
            "urgency": "none",
            "data_status": "missing",
            "title": "Decision held",
            "message": "Soil moisture is missing, so irrigation advice cannot be generated safely.",
            "reason": "Moisture is the primary irrigation signal and was not available in the latest reading.",
            "condition_summary": "missing_moisture",
            "factors": factors,
        }

    if moisture_status == "dry" and rain["status"] == "none_recent":
        forecast_rain_expected = bool((forecast.get("signals") or {}).get("rain_expected"))
        forecast_hot = bool((forecast.get("signals") or {}).get("hot_expected"))
        forecast_windy = bool((forecast.get("signals") or {}).get("windy_expected"))
        if forecast_rain_expected:
            return {
                "decision": DECISION_DELAY,
                "urgency": "medium" if weather_demand == "high" else "low",
                "data_status": "fresh",
                "title": "Delay irrigation",
                "message": "Dry soil was detected, but the near-term forecast suggests rain may arrive soon.",
                "reason": "Moisture is below target, but the forecast layer indicates rain within the planning horizon.",
                "condition_summary": "dry_soil_forecast_rain_expected",
                "factors": factors,
            }

        urgency = "high" if weather_demand == "high" or forecast_hot or forecast_windy else "medium"
        return {
            "decision": DECISION_START,
            "urgency": urgency,
            "data_status": "fresh",
            "title": "Start irrigation now",
            "message": "Soil moisture is below target and current field demand is increasing.",
            "reason": "Moisture is below the lower target band, no effective recent rainfall was detected, and the forecast does not suggest near-term rain.",
            "condition_summary": f"dry_soil_no_recent_rain_{weather_demand}_demand",
            "factors": factors,
        }

    if moisture_status == "dry" and rain["status"] == "effective_recent_rain":
        return {
            "decision": DECISION_DELAY,
            "urgency": "medium" if weather_demand == "high" else "low",
            "data_status": "fresh",
            "title": "Delay irrigation",
            "message": "Recent rainfall may have reduced immediate water requirement. Monitor moisture before starting irrigation.",
            "reason": "Soil is still below target, but effective rainfall was detected within the configured rain window.",
            "condition_summary": "dry_soil_recent_effective_rain",
            "factors": factors,
        }

    if moisture_status == "acceptable" and rain["status"] == "effective_recent_rain":
        return {
            "decision": DECISION_DELAY,
            "urgency": "low",
            "data_status": "fresh",
            "title": "Delay irrigation",
            "message": "Rainfall has already reduced immediate water need.",
            "reason": "Soil moisture is acceptable and effective recent rainfall was detected.",
            "condition_summary": "acceptable_moisture_recent_rain",
            "factors": factors,
        }

    forecast_rain_expected = bool((forecast.get("signals") or {}).get("rain_expected"))
    if moisture_status == "acceptable" and forecast_rain_expected:
        return {
            "decision": DECISION_DELAY,
            "urgency": "low",
            "data_status": "fresh",
            "title": "Delay irrigation",
            "message": "Soil moisture is acceptable and the forecast suggests rain may arrive soon.",
            "reason": "The forecast layer indicates near-term rain, so irrigation can wait.",
            "condition_summary": "acceptable_moisture_forecast_rain_expected",
            "factors": factors,
        }

    return {
        "decision": DECISION_NONE,
        "urgency": "none",
        "data_status": "fresh",
        "title": "No irrigation needed",
        "message": "Soil moisture is currently within or above the target range.",
        "reason": "Moisture is not below the configured lower target band, so irrigation is not required now.",
        "condition_summary": f"{moisture_status}_moisture",
        "factors": factors,
    }


def _advisory_to_response(station: Station, advisory: IrrigationAdvisory) -> IrrigationAdvisoryResponse:
    return IrrigationAdvisoryResponse(
        id=advisory.id,
        device_id=station.device_id,
        station_name=station.name,
        reading_id=advisory.reading_id,
        rule_version=advisory.rule_version,
        generated_at=advisory.generated_at,
        decision=advisory.decision,
        urgency=advisory.urgency,
        data_status=advisory.data_status,
        title=advisory.title,
        message=advisory.message,
        reason=advisory.reason,
        condition_summary=advisory.condition_summary,
        factors=_json_load(advisory.factors_json),
        sensor_snapshot=_json_load(advisory.sensor_snapshot_json),
        profile_snapshot=_json_load(advisory.profile_snapshot_json),
    )


def create_irrigation_advisory_for_reading(
    db: Session,
    station: Station,
    reading: SensorReading,
    *,
    commit: bool = True,
) -> IrrigationAdvisory | None:
    profile = ensure_irrigation_profile(db, station)
    if not profile.smart_irrigation_enabled:
        return None

    # A load_runtime_settings() call used to sit here purely for its side effect
    # of creating the station/settings rows, discarding the result — two SELECTs
    # and a possible COMMIT on every reading. create_reading_sync already
    # guarantees those rows exist, so it has been removed.
    decision = _evaluate_irrigation(db, station, reading, profile)
    advisory = IrrigationAdvisory(
        station_id=station.id,
        reading_id=reading.id,
        rule_version=RULE_VERSION,
        generated_at=datetime.now(timezone.utc),
        decision=decision["decision"],
        urgency=decision["urgency"],
        data_status=decision["data_status"],
        title=decision["title"],
        message=decision["message"],
        reason=decision["reason"],
        condition_summary=decision["condition_summary"],
        factors_json=_json_dump(decision["factors"]),
        sensor_snapshot_json=_json_dump(_reading_snapshot(station, reading)),
        profile_snapshot_json=_json_dump(_profile_snapshot(profile)),
    )
    db.add(advisory)
    db.flush()

    if commit:
        db.commit()
        db.refresh(station)
        db.refresh(advisory)

    return advisory


def _latest_reading_row(db: Session, station: Station) -> SensorReading | None:
    return db.scalar(
        select(SensorReading)
        .join(LatestReading, LatestReading.reading_id == SensorReading.id)
        .where(LatestReading.station_id == station.id)
    )


def get_latest_irrigation_advisory(
    db: Session,
    device_id: str,
    *,
    regenerate: bool = True,
) -> IrrigationAdvisoryResponse | None:
    station = db.scalar(select(Station).where(Station.device_id == device_id))
    if station is None:
        return None

    reading = _latest_reading_row(db, station)
    if reading is None:
        return None

    profile = ensure_irrigation_profile(db, station)
    if not profile.smart_irrigation_enabled:
        db.commit()
        return None

    advisory = db.scalar(
        select(IrrigationAdvisory)
        .where(IrrigationAdvisory.station_id == station.id)
        .order_by(desc(IrrigationAdvisory.generated_at), desc(IrrigationAdvisory.id))
        .limit(1)
    )

    current_profile_snapshot = _profile_snapshot(profile)
    advisory_profile_snapshot = (
        _json_load(advisory.profile_snapshot_json)
        if advisory is not None
        else {}
    )
    advisory_is_current = (
        advisory is not None
        and advisory.reading_id == reading.id
        and advisory.rule_version == RULE_VERSION
        and advisory_profile_snapshot == current_profile_snapshot
    )

    if regenerate and not advisory_is_current:
        advisory = create_irrigation_advisory_for_reading(db, station, reading, commit=True)
    elif advisory is not None:
        db.commit()
        db.refresh(station)

    return None if advisory is None else _advisory_to_response(station, advisory)


def list_irrigation_advisories(
    db: Session,
    device_id: str,
    *,
    limit: int,
) -> tuple[list[IrrigationAdvisoryResponse], int]:
    station = db.scalar(select(Station).where(Station.device_id == device_id))
    if station is None:
        return [], 0

    safe_limit = max(1, min(limit, 1000))
    total = db.scalar(
        select(func.count()).select_from(IrrigationAdvisory).where(IrrigationAdvisory.station_id == station.id)
    ) or 0
    rows = db.scalars(
        select(IrrigationAdvisory)
        .where(IrrigationAdvisory.station_id == station.id)
        .order_by(desc(IrrigationAdvisory.generated_at), desc(IrrigationAdvisory.id))
        .limit(safe_limit)
    ).all()

    return [_advisory_to_response(station, row) for row in rows], total


def create_irrigation_action(
    db: Session,
    device_id: str,
    payload: IrrigationActionRequest,
) -> IrrigationActionResponse:
    if payload.action not in ALLOWED_ACTIONS:
        raise ValueError(f"Unsupported irrigation action: {payload.action}")

    station = get_or_create_station(db, device_id)
    advisory: IrrigationAdvisory | None = None
    if payload.advisory_id is not None:
        advisory = db.scalar(
            select(IrrigationAdvisory).where(
                IrrigationAdvisory.id == payload.advisory_id,
                IrrigationAdvisory.station_id == station.id,
            )
        )
        if advisory is None:
            raise ValueError("advisory_id does not belong to this station")

    row = IrrigationActionLog(
        station_id=station.id,
        advisory_id=None if advisory is None else advisory.id,
        action=payload.action,
        actor_id=payload.actor_id,
        note=payload.note,
        action_metadata_json=_json_dump(payload.metadata),
    )
    db.add(row)
    db.commit()
    db.refresh(row)

    return IrrigationActionResponse(
        id=row.id,
        device_id=station.device_id,
        advisory_id=row.advisory_id,
        action=row.action,
        actor_id=row.actor_id,
        note=row.note,
        metadata=_json_load(row.action_metadata_json),
        created_at=row.created_at,
    )
