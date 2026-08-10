from __future__ import annotations

import json
import threading
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

from app.config import Settings


OPEN_METEO_BASE_URL = "https://api.open-meteo.com/v1/forecast"
DEFAULT_FORECAST_HOURS = 24
DEFAULT_CACHE_MINUTES = 30
RAIN_PROBABILITY_THRESHOLD = 50
RAIN_AMOUNT_THRESHOLD_MM = 1.0


@dataclass(frozen=True)
class ForecastKey:
    provider: str
    latitude: float
    longitude: float
    timezone_name: str
    horizon_hours: int
    cache_bucket: int


_FORECAST_CACHE: dict[ForecastKey, dict[str, Any]] = {}
_FORECAST_CACHE_LOCK = threading.Lock()


def _normalize_provider(value: str | None) -> str:
    provider = (value or "open-meteo").strip().lower()
    return provider or "open-meteo"


def _parse_float(value: float | str | None) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    stripped = str(value).strip()
    if not stripped:
        return None
    try:
        return float(stripped)
    except ValueError:
        return None


def _build_open_meteo_url(
    settings: Settings,
    horizon_hours: int,
    *,
    latitude: float,
    longitude: float,
    timezone_name: str,
) -> str:
    params = {
        "latitude": str(latitude),
        "longitude": str(longitude),
        "timezone": timezone_name,
        "forecast_hours": str(horizon_hours),
        "hourly": ",".join(
            [
                "temperature_2m",
                "precipitation_probability",
                "precipitation",
                "rain",
                "wind_speed_10m",
                "wind_gusts_10m",
                "cloud_cover",
                "relative_humidity_2m",
                "weather_code",
            ]
        ),
    }
    return f"{OPEN_METEO_BASE_URL}?{urllib.parse.urlencode(params)}"


def _parse_iso_timestamp(value: str) -> datetime | None:
    try:
        candidate = value.replace("Z", "+00:00")
        parsed = datetime.fromisoformat(candidate)
    except ValueError:
        return None

    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _select_forecast_points(payload: dict[str, Any], horizon_hours: int) -> list[dict[str, Any]]:
    hourly = payload.get("hourly") if isinstance(payload.get("hourly"), dict) else {}
    times = hourly.get("time") if isinstance(hourly.get("time"), list) else []
    if not times:
        return []

    fields = {
        "temperature_2m": hourly.get("temperature_2m") or [],
        "precipitation_probability": hourly.get("precipitation_probability") or [],
        "precipitation": hourly.get("precipitation") or [],
        "rain": hourly.get("rain") or [],
        "wind_speed_10m": hourly.get("wind_speed_10m") or [],
        "wind_gusts_10m": hourly.get("wind_gusts_10m") or [],
        "cloud_cover": hourly.get("cloud_cover") or [],
        "relative_humidity_2m": hourly.get("relative_humidity_2m") or [],
        "weather_code": hourly.get("weather_code") or [],
    }

    now = datetime.now(timezone.utc)
    selected: list[dict[str, Any]] = []
    for index, raw_time in enumerate(times):
        timestamp = _parse_iso_timestamp(str(raw_time))
        if timestamp is None:
            continue
        if timestamp < now:
            continue
        if timestamp > now + timedelta(hours=horizon_hours):
            break

        selected.append(
            {
                "timestamp": timestamp.isoformat(),
                "temperature_c": fields["temperature_2m"][index] if index < len(fields["temperature_2m"]) else None,
                "precipitation_probability": (
                    fields["precipitation_probability"][index]
                    if index < len(fields["precipitation_probability"])
                    else None
                ),
                "precipitation_mm": fields["precipitation"][index] if index < len(fields["precipitation"]) else None,
                "rain_mm": fields["rain"][index] if index < len(fields["rain"]) else None,
                "wind_speed_ms": fields["wind_speed_10m"][index] if index < len(fields["wind_speed_10m"]) else None,
                "wind_gust_ms": fields["wind_gusts_10m"][index] if index < len(fields["wind_gusts_10m"]) else None,
                "cloud_cover_pct": fields["cloud_cover"][index] if index < len(fields["cloud_cover"]) else None,
                "humidity_pct": (
                    fields["relative_humidity_2m"][index]
                    if index < len(fields["relative_humidity_2m"])
                    else None
                ),
                "weather_code": fields["weather_code"][index] if index < len(fields["weather_code"]) else None,
            }
        )

    return selected


def _summarize_points(points: list[dict[str, Any]]) -> dict[str, Any]:
    def _values(key: str) -> list[float]:
        values: list[float] = []
        for point in points:
            raw = point.get(key)
            if isinstance(raw, (int, float)):
                values.append(float(raw))
        return values

    rain_values = _values("rain_mm")
    precipitation_values = _values("precipitation_mm")
    rain_probability_values = _values("precipitation_probability")
    temp_values = _values("temperature_c")
    wind_values = _values("wind_speed_ms")
    gust_values = _values("wind_gust_ms")
    cloud_values = _values("cloud_cover_pct")
    humidity_values = _values("humidity_pct")

    rain_total = round(sum(rain_values) if rain_values else sum(precipitation_values), 3)
    rain_probability_peak = max(rain_probability_values) if rain_probability_values else None
    rain_expected = bool(
        (rain_total >= RAIN_AMOUNT_THRESHOLD_MM)
        or (rain_probability_peak is not None and rain_probability_peak >= RAIN_PROBABILITY_THRESHOLD)
    )

    return {
        "rain_total_mm": rain_total,
        "rain_probability_peak": rain_probability_peak,
        "rain_expected": rain_expected,
        "temperature_min_c": round(min(temp_values), 2) if temp_values else None,
        "temperature_max_c": round(max(temp_values), 2) if temp_values else None,
        "wind_max_ms": round(max(wind_values), 2) if wind_values else None,
        "gust_max_ms": round(max(gust_values), 2) if gust_values else None,
        "cloud_cover_max_pct": round(max(cloud_values), 2) if cloud_values else None,
        "humidity_min_pct": round(min(humidity_values), 2) if humidity_values else None,
    }


def _classify_forecast(summary: dict[str, Any], horizon_hours: int) -> dict[str, Any]:
    rain_total = summary.get("rain_total_mm") or 0.0
    rain_probability_peak = summary.get("rain_probability_peak")
    wind_max = summary.get("wind_max_ms")
    temp_max = summary.get("temperature_max_c")

    labels: list[str] = []
    if summary.get("rain_expected"):
        labels.append("rain_expected")
    if isinstance(temp_max, (int, float)) and temp_max >= 35:
        labels.append("hot")
    if isinstance(wind_max, (int, float)) and wind_max >= 6:
        labels.append("windy")

    if rain_total >= 3 or (rain_probability_peak is not None and rain_probability_peak >= 80):
        confidence = "high"
    elif rain_total >= 1 or (rain_probability_peak is not None and rain_probability_peak >= 50):
        confidence = "medium"
    else:
        confidence = "low"

    if not labels:
        labels.append("clear")

    return {
        "confidence": confidence,
        "labels": labels,
        "horizon_hours": horizon_hours,
    }


def fetch_weather_forecast(
    settings: Settings,
    *,
    latitude: float | None = None,
    longitude: float | None = None,
    timezone_name: str | None = None,
) -> dict[str, Any] | None:
    if not settings.weather_forecast_enabled:
        return None

    latitude = _parse_float(latitude if latitude is not None else settings.weather_forecast_latitude)
    longitude = _parse_float(longitude if longitude is not None else settings.weather_forecast_longitude)
    if latitude is None or longitude is None:
        return None

    horizon_hours = max(1, min(72, int(settings.weather_forecast_hours or DEFAULT_FORECAST_HOURS)))
    cache_minutes = max(5, int(settings.weather_forecast_cache_minutes or DEFAULT_CACHE_MINUTES))
    cache_bucket = int(datetime.now(timezone.utc).timestamp() // (cache_minutes * 60))
    key = ForecastKey(
        provider=_normalize_provider(settings.weather_forecast_provider),
        latitude=round(latitude, 4),
        longitude=round(longitude, 4),
        timezone_name=(timezone_name or settings.weather_forecast_timezone or "UTC").strip() or "UTC",
        horizon_hours=horizon_hours,
        cache_bucket=cache_bucket,
    )

    with _FORECAST_CACHE_LOCK:
        cached = _FORECAST_CACHE.get(key)
    if cached is not None:
        return cached

    if key.provider != "open-meteo":
        return None

    url = _build_open_meteo_url(
        settings,
        horizon_hours,
        latitude=latitude,
        longitude=longitude,
        timezone_name=timezone_name or settings.weather_forecast_timezone or "UTC",
    )
    request = urllib.request.Request(url, headers={"User-Agent": "CropConnect/1.0"})

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except Exception:
        return None

    if not isinstance(payload, dict):
        return None

    points = _select_forecast_points(payload, horizon_hours)
    summary = _summarize_points(points)
    classification = _classify_forecast(summary, horizon_hours)
    forecast = {
        "provider": key.provider,
        "latitude": latitude,
        "longitude": longitude,
        "timezone": payload.get("timezone") or timezone_name or settings.weather_forecast_timezone or "UTC",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "horizon_hours": horizon_hours,
        "summary": summary,
        "classification": classification,
        "hourly": points,
    }

    with _FORECAST_CACHE_LOCK:
        _FORECAST_CACHE[key] = forecast

    return forecast
