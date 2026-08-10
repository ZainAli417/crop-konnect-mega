from datetime import datetime, timedelta, timezone

from app.schemas import AlertResponse, ReadingResponse, SensorHealthResponse


STALE_AFTER_MINUTES = 10


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def classify_soil_moisture(value: float | None) -> str:
    if value is None:
        return "unknown"
    if value < 20:
        return "low"
    if value <= 60:
        return "normal"
    return "high"


def classify_soil_temperature(value: float | None) -> str:
    if value is None:
        return "unknown"
    if value < 15:
        return "cool"
    if value <= 35:
        return "normal"
    return "hot"


def classify_rain(value: float | None) -> str:
    if value is None:
        return "unknown"
    return "detected" if value > 0 else "not_detected"


def classify_wind(value: float | None) -> str:
    if value is None:
        return "unknown"
    if value < 5:
        return "calm"
    if value <= 10:
        return "moderate"
    return "high"


def classify_uv(value: float | None) -> str:
    if value is None:
        return "unknown"
    if value < 3:
        return "low"
    if value <= 6:
        return "moderate"
    if value <= 8:
        return "high"
    return "very_high"


def classify_ec(value: float | None) -> str:
    if value is None:
        return "unknown"
    if value < 15:
        return "low"
    if value <= 30:
        return "normal"
    return "high"


def compute_sensor_health(
    latest: ReadingResponse | None,
    enabled: dict[str, bool] | None = None,
) -> dict[str, SensorHealthResponse]:
    now = datetime.now(timezone.utc)
    enabled_sensors = enabled or {"wind": False, "soil": False, "rain": False, "uv": False}
    if latest is None:
        return {
            "wind": SensorHealthResponse(
                status="disabled" if not enabled_sensors.get("wind", False) else "offline",
                last_updated=None,
                freshness="disabled" if not enabled_sensors.get("wind", False) else "missing",
            ),
            "soil": SensorHealthResponse(
                status="disabled" if not enabled_sensors.get("soil", False) else "offline",
                last_updated=None,
                freshness="disabled" if not enabled_sensors.get("soil", False) else "missing",
            ),
            "rain": SensorHealthResponse(
                status="disabled" if not enabled_sensors.get("rain", False) else "offline",
                last_updated=None,
                freshness="disabled" if not enabled_sensors.get("rain", False) else "missing",
            ),
            "uv": SensorHealthResponse(
                status="disabled" if not enabled_sensors.get("uv", False) else "offline",
                last_updated=None,
                freshness="disabled" if not enabled_sensors.get("uv", False) else "missing",
            ),
        }

    recorded_at = _as_utc(latest.recorded_at)
    freshness = "fresh" if now - recorded_at <= timedelta(minutes=STALE_AFTER_MINUTES) else "stale"

    def status_for(values: list[float | str | None]) -> str:
        if all(value is None for value in values):
            return "offline" if freshness == "fresh" else "stale"
        return "online" if freshness == "fresh" else "stale"

    return {
        "wind": SensorHealthResponse(
            status="disabled"
            if not enabled_sensors.get("wind", False)
            else status_for([latest.ws, latest.wd_deg, latest.wd_dir]),
            last_updated=None if not enabled_sensors.get("wind", False) else latest.recorded_at,
            freshness="disabled" if not enabled_sensors.get("wind", False) else freshness,
        ),
        "soil": SensorHealthResponse(
            status="disabled"
            if not enabled_sensors.get("soil", False)
            else status_for([latest.moist, latest.temp, latest.ec, latest.n, latest.p, latest.k, latest.ph]),
            last_updated=None if not enabled_sensors.get("soil", False) else latest.recorded_at,
            freshness="disabled" if not enabled_sensors.get("soil", False) else freshness,
        ),
        "rain": SensorHealthResponse(
            status="disabled" if not enabled_sensors.get("rain", False) else status_for([latest.rain]),
            last_updated=None if not enabled_sensors.get("rain", False) else latest.recorded_at,
            freshness="disabled" if not enabled_sensors.get("rain", False) else freshness,
        ),
        "uv": SensorHealthResponse(
            status="disabled" if not enabled_sensors.get("uv", False) else status_for([latest.solar]),
            last_updated=None if not enabled_sensors.get("uv", False) else latest.recorded_at,
            freshness="disabled" if not enabled_sensors.get("uv", False) else freshness,
        ),
    }


def build_alerts(latest: ReadingResponse | None, sensor_health: dict[str, SensorHealthResponse]) -> list[AlertResponse]:
    if latest is None:
        return [
            AlertResponse(
                type="station_offline",
                severity="critical",
                title="No Station Data",
                message="No readings are currently available for this station.",
                timestamp=None,
            )
        ]

    alerts: list[AlertResponse] = []
    timestamp = latest.recorded_at

    if latest.moist is not None and latest.moist < 20:
        alerts.append(
            AlertResponse(
                type="low_moisture",
                severity="warning",
                title="Low Soil Moisture",
                message="Soil moisture is below the recommended operating range.",
                timestamp=timestamp,
            )
        )

    if latest.temp is not None and latest.temp > 35:
        alerts.append(
            AlertResponse(
                type="high_temperature",
                severity="warning",
                title="High Soil Temperature",
                message="Soil temperature is in a high range and may stress crops.",
                timestamp=timestamp,
            )
        )

    if latest.rain is not None and latest.rain > 0:
        alerts.append(
            AlertResponse(
                type="rain_detected",
                severity="info",
                title="Rain Detected",
                message="Rainfall is currently being detected in the field.",
                timestamp=timestamp,
            )
        )

    if latest.ws is not None and latest.ws > 10:
        alerts.append(
            AlertResponse(
                type="high_wind",
                severity="warning",
                title="High Wind Speed",
                message="Wind conditions may be unsafe for spraying operations.",
                timestamp=timestamp,
            )
        )

    if latest.solar is not None and latest.solar > 6:
        alerts.append(
            AlertResponse(
                type="high_uv",
                severity="warning",
                title="High UV Exposure",
                message="UV exposure is elevated and may require crop protection planning.",
                timestamp=timestamp,
            )
        )

    if latest.ec is not None and latest.ec > 30:
        alerts.append(
            AlertResponse(
                type="high_ec",
                severity="warning",
                title="High Soil EC",
                message="Soil EC is elevated and may indicate salinity stress.",
                timestamp=timestamp,
            )
        )

    for sensor_name, health in sensor_health.items():
        if health.status in {"offline", "stale"}:
            alerts.append(
                AlertResponse(
                    type=f"{sensor_name}_sensor_{health.status}",
                    severity="critical" if health.status == "offline" else "warning",
                    title=f"{sensor_name.upper()} Sensor {health.status.title()}",
                    message=f"The {sensor_name} sensor is currently {health.status}.",
                    timestamp=health.last_updated,
                )
            )

    return alerts


def derive_overall_status(alerts: list[AlertResponse]) -> str:
    if any(alert.severity == "critical" for alert in alerts):
        return "critical"
    if any(alert.severity == "warning" for alert in alerts):
        return "attention"
    return "normal"


def build_conditions(latest: ReadingResponse | None) -> dict[str, str]:
    if latest is None:
        return {
            "soil_moisture": "unknown",
            "temperature": "unknown",
            "rain": "unknown",
            "wind": "unknown",
            "uv": "unknown",
            "ec": "unknown",
        }

    return {
        "soil_moisture": classify_soil_moisture(latest.moist),
        "temperature": classify_soil_temperature(latest.temp),
        "rain": classify_rain(latest.rain),
        "wind": classify_wind(latest.ws),
        "uv": classify_uv(latest.solar),
        "ec": classify_ec(latest.ec),
    }
