from collections import defaultdict
from datetime import datetime, timedelta, timezone
import logging
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import WebSocket
from sqlalchemy import Select, desc, func, select
from sqlalchemy.orm import Session

from app.config import get_settings
from app.excel_logger import append_reading_to_excel_log
from app.models import GpsReading, LatestReading, SensorReading, Station
from app.monitoring import build_alerts, build_conditions, compute_sensor_health, derive_overall_status
from app.irrigation import create_irrigation_advisory_for_reading
from app.schemas import (
    AdminStationListItemResponse,
    AdminStationOverviewResponse,
    IngestRequest,
    MonitoringStatusResponse,
    GpsReadingResponse,
    ReadingResponse,
    StationSummaryResponse,
    StationSettingsResponse,
    TrendPointResponse,
    TrendsResponse,
)
from app.station_settings import ensure_station_settings, fetch_station_settings, get_enabled_sensor_groups


logger = logging.getLogger(__name__)


class LiveConnectionManager:
    def __init__(self) -> None:
        self.connections: dict[str, set[WebSocket]] = defaultdict(set)

    async def connect(self, device_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        self.connections[device_id].add(websocket)

    def disconnect(self, device_id: str, websocket: WebSocket) -> None:
        self.connections[device_id].discard(websocket)
        if not self.connections[device_id]:
            self.connections.pop(device_id, None)

    async def broadcast(self, device_id: str, payload: dict) -> None:
        stale_connections: list[WebSocket] = []
        for websocket in self.connections.get(device_id, set()):
            try:
                await websocket.send_json(payload)
            except Exception:
                stale_connections.append(websocket)

        for websocket in stale_connections:
            self.disconnect(device_id, websocket)


live_manager = LiveConnectionManager()


async def run_broadcast(device_id: str, payload: dict) -> None:
    await live_manager.broadcast(device_id, payload)


def get_or_create_station(db: Session, device_id: str, station_name: str | None = None) -> Station:
    station = db.scalar(select(Station).where(Station.device_id == device_id))
    if station:
        if station_name and station.name != station_name:
            station.name = station_name
        return station

    station = Station(device_id=device_id, name=station_name)
    db.add(station)
    db.flush()
    return station


def to_reading_response(reading: SensorReading, station: Station) -> ReadingResponse:
    return ReadingResponse(
        id=reading.id,
        device_id=station.device_id,
        station_name=station.name,
        recorded_at=reading.recorded_at,
        received_at=reading.received_at,
        ws=reading.wind_speed,
        wd_deg=reading.wind_direction_degrees,
        wd_dir=reading.wind_direction_label,
        moist=reading.soil_moisture,
        temp=reading.soil_temperature,
        ec=reading.soil_ec,
        n=reading.soil_nitrogen,
        p=reading.soil_phosphorus,
        k=reading.soil_potassium,
        ph=reading.soil_ph,
        rain=reading.rainfall,
        solar=reading.solar_radiation,
    )


def to_gps_reading_response(reading: GpsReading, station: Station) -> GpsReadingResponse:
    return GpsReadingResponse(
        id=reading.id,
        device_id=station.device_id,
        station_name=station.name,
        recorded_at=reading.recorded_at,
        received_at=reading.received_at,
        latitude=reading.latitude,
        longitude=reading.longitude,
        altitude_m=reading.altitude_m,
        speed_kmh=reading.speed_kmh,
        heading_deg=reading.heading_deg,
        satellites=reading.satellites,
        nmea_time=reading.nmea_time,
        address=reading.address,
        moved_meters=reading.moved_meters,
    )


def create_gps_fix_sync(
    db: Session,
    *,
    device_id: str,
    station_name: str | None = None,
    recorded_at: datetime,
    latitude: float,
    longitude: float,
    altitude_m: float | None = None,
    speed_kmh: float | None = None,
    heading_deg: float | None = None,
    satellites: str | None = None,
    nmea_time: str | None = None,
    address: str | None = None,
    moved_meters: float | None = None,
) -> GpsReadingResponse:
    try:
        station = get_or_create_station(db, device_id, station_name)
        reading = GpsReading(
            station_id=station.id,
            recorded_at=recorded_at,
            latitude=latitude,
            longitude=longitude,
            altitude_m=altitude_m,
            speed_kmh=speed_kmh,
            heading_deg=heading_deg,
            satellites=satellites,
            nmea_time=nmea_time,
            address=address,
            moved_meters=moved_meters,
        )
        db.add(reading)
        db.commit()
        db.refresh(reading)
        db.refresh(station)
        return to_gps_reading_response(reading, station)
    except Exception:
        db.rollback()
        raise


def get_latest_gps_fix(db: Session, device_id: str) -> GpsReadingResponse | None:
    query = (
        select(GpsReading, Station)
        .join(Station, Station.id == GpsReading.station_id)
        .where(Station.device_id == device_id)
        .order_by(desc(GpsReading.recorded_at), desc(GpsReading.id))
        .limit(1)
    )
    row = db.execute(query).first()
    if not row:
        return None

    reading, station = row
    return to_gps_reading_response(reading, station)


def list_gps_fixes(db: Session, device_id: str, limit: int) -> tuple[list[GpsReadingResponse], int]:
    filters = [Station.device_id == device_id]
    base_query = (
        select(GpsReading, Station)
        .join(Station, Station.id == GpsReading.station_id)
        .where(*filters)
    )
    count_query = (
        select(func.count())
        .select_from(GpsReading)
        .join(Station, Station.id == GpsReading.station_id)
        .where(*filters)
    )

    rows = db.execute(base_query.order_by(desc(GpsReading.recorded_at)).limit(limit)).all()
    total = db.scalar(count_query) or 0

    return [to_gps_reading_response(reading, station) for reading, station in rows], total


def _parse_schedule_clock(value: str | None, fallback: str) -> datetime.time:
    candidate = (value or fallback).strip()
    try:
        hour, minute = candidate.split(":")
        return datetime.strptime(f"{int(hour):02d}:{int(minute):02d}", "%H:%M").time()
    except Exception:
        hour, minute = fallback.split(":")
        return datetime.strptime(f"{int(hour):02d}:{int(minute):02d}", "%H:%M").time()


def _schedule_now(schedule, now: datetime | None = None) -> datetime:
    try:
        tzinfo = ZoneInfo(schedule.timezone)
    except ZoneInfoNotFoundError:
        tzinfo = timezone.utc

    if now is None:
        return datetime.now(tzinfo)
    if now.tzinfo is None:
        return now.replace(tzinfo=tzinfo)
    return now.astimezone(tzinfo)


def _schedule_run_times(schedule) -> list[datetime.time]:
    values: list[datetime.time] = []
    for item in schedule.run_times or []:
        try:
            values.append(_parse_schedule_clock(item, schedule.start_time))
        except Exception:
            continue

    if values:
        return values

    return [_parse_schedule_clock(schedule.start_time, "00:00")]


def _frequency_day_matches(schedule, local_date) -> bool:
    active_days = set(schedule.days or [])
    if active_days and WEEKDAY_KEYS[local_date.weekday()] not in active_days:
        return False

    days_since_anchor = (local_date - schedule.anchor_date).days
    if days_since_anchor < 0:
        return False

    interval_days = max(1, int(schedule.interval_days or 1))
    return days_since_anchor % interval_days == 0


def _is_schedule_active(schedule, now: datetime | None = None) -> bool:
    if not schedule.enabled:
        return True

    local_now = _schedule_now(schedule, now)
    current_weekday = WEEKDAY_KEYS[local_now.weekday()]
    previous_weekday = WEEKDAY_KEYS[(local_now.weekday() - 1) % 7]
    current_time = local_now.time().replace(second=0, microsecond=0)

    if schedule.mode == "frequency":
        if not _frequency_day_matches(schedule, local_now.date()):
            return False

        for run_time in _schedule_run_times(schedule):
            candidate = datetime.combine(local_now.date(), run_time, tzinfo=local_now.tzinfo)
            if candidate <= local_now < candidate + timedelta(minutes=1):
                return True
        return False

    active_days = set(schedule.days or [])
    if not active_days:
        return False

    start_time = _parse_schedule_clock(schedule.start_time, "00:00")
    end_time = _parse_schedule_clock(schedule.end_time, "23:59")

    if start_time <= end_time:
        return current_weekday in active_days and start_time <= current_time <= end_time

    if current_time >= start_time:
        return current_weekday in active_days
    if current_time <= end_time:
        return previous_weekday in active_days
    return False


def create_reading(db: Session, payload: IngestRequest) -> ReadingResponse:
    return create_reading_sync(db, payload)


_settings_ensured_station_ids: set[int] = set()


def create_reading_sync(db: Session, payload: IngestRequest) -> ReadingResponse:
    station = get_or_create_station(db, payload.device_id, payload.station_name)

    # The settings row only has to be created once per station per process. This
    # used to run two extra SELECTs on every single reading insert.
    if station.id not in _settings_ensured_station_ids:
        ensure_station_settings(db, station, env=get_settings())
        _settings_ensured_station_ids.add(station.id)

    recorded_at = payload.recorded_at or datetime.now(timezone.utc)
    # Set explicitly rather than relying on the server default: an unloaded
    # server_default column would force a SELECT to read it back for the
    # response, on every reading.
    received_at = datetime.now(timezone.utc)

    reading = SensorReading(
        station_id=station.id,
        recorded_at=recorded_at,
        received_at=received_at,
        wind_speed=payload.data.ws,
        wind_direction_degrees=payload.data.wd_deg,
        wind_direction_label=payload.data.wd_dir,
        soil_moisture=payload.data.moist,
        soil_temperature=payload.data.temp,
        soil_ec=payload.data.ec,
        soil_nitrogen=payload.data.n,
        soil_phosphorus=payload.data.p,
        soil_potassium=payload.data.k,
        soil_ph=payload.data.ph,
        rainfall=payload.data.rain,
        solar_radiation=payload.data.solar,
    )
    db.add(reading)
    db.flush()

    latest = db.scalar(select(LatestReading).where(LatestReading.station_id == station.id))
    if latest:
        latest.reading_id = reading.id
    else:
        db.add(LatestReading(station_id=station.id, reading_id=reading.id))

    create_irrigation_advisory_for_reading(db, station, reading, commit=False)

    # Capture what the response needs before the commit expires the instances,
    # so we do not pay for two extra SELECTs re-loading rows we just wrote.
    reading_id = reading.id
    device_id = station.device_id
    station_name = station.name

    db.commit()

    response = ReadingResponse(
        id=reading_id,
        device_id=device_id,
        station_name=station_name,
        recorded_at=recorded_at,
        received_at=received_at,
        ws=payload.data.ws,
        wd_deg=payload.data.wd_deg,
        wd_dir=payload.data.wd_dir,
        moist=payload.data.moist,
        temp=payload.data.temp,
        ec=payload.data.ec,
        n=payload.data.n,
        p=payload.data.p,
        k=payload.data.k,
        ph=payload.data.ph,
        rain=payload.data.rain,
        solar=payload.data.solar,
    )
    try:
        append_reading_to_excel_log(response, get_settings())
    except Exception:
        logger.exception("Failed to append reading %s to local Excel log", response.id)
    return response


def get_latest_reading(db: Session, device_id: str) -> ReadingResponse | None:
    query = (
        select(SensorReading, Station)
        .join(Station, Station.id == SensorReading.station_id)
        .join(LatestReading, LatestReading.reading_id == SensorReading.id)
        .where(Station.device_id == device_id)
    )
    row = db.execute(query).first()
    if not row:
        return None

    reading, station = row
    return to_reading_response(reading, station)


def list_readings(
    db: Session,
    device_id: str,
    limit: int,
    recorded_from: datetime | None = None,
    recorded_to: datetime | None = None,
) -> tuple[list[ReadingResponse], int]:
    filters = [Station.device_id == device_id]
    if recorded_from:
        filters.append(SensorReading.recorded_at >= recorded_from)
    if recorded_to:
        filters.append(SensorReading.recorded_at <= recorded_to)

    base_query: Select = select(SensorReading, Station).join(Station, Station.id == SensorReading.station_id).where(*filters)
    count_query = select(func.count()).select_from(SensorReading).join(Station, Station.id == SensorReading.station_id).where(*filters)

    rows = db.execute(base_query.order_by(desc(SensorReading.recorded_at)).limit(limit)).all()
    total = db.scalar(count_query) or 0

    return [to_reading_response(reading, station) for reading, station in rows], total


def build_summary(db: Session, device_id: str, hours: int) -> dict | None:
    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    station = db.scalar(select(Station).where(Station.device_id == device_id))
    if not station:
        return None

    aggregate_query = (
        select(
            func.count(SensorReading.id),
            func.max(SensorReading.recorded_at),
            func.avg(SensorReading.wind_speed),
            func.avg(SensorReading.soil_moisture),
            func.avg(SensorReading.soil_temperature),
            func.avg(SensorReading.rainfall),
            func.avg(SensorReading.solar_radiation),
        )
        .where(SensorReading.station_id == station.id, SensorReading.recorded_at >= since)
    )
    count, last_recorded_at, avg_ws, avg_moist, avg_temp, avg_rain, avg_solar = db.execute(aggregate_query).one()

    return {
        "device_id": device_id,
        "hours": hours,
        "total_readings": count or 0,
        "last_recorded_at": last_recorded_at,
        "averages": {
            "ws": round(avg_ws, 2) if avg_ws is not None else None,
            "moist": round(avg_moist, 2) if avg_moist is not None else None,
            "temp": round(avg_temp, 2) if avg_temp is not None else None,
            "rain": round(avg_rain, 2) if avg_rain is not None else None,
            "solar": round(avg_solar, 2) if avg_solar is not None else None,
        },
    }


def clamp_limit(limit: int) -> int:
    settings = get_settings()
    return max(1, min(limit, settings.max_history_limit))


def build_monitoring_status(db: Session, device_id: str) -> MonitoringStatusResponse | None:
    latest = get_latest_reading(db, device_id)
    if latest is None:
        return None

    enabled_groups = get_enabled_sensor_groups(db, device_id) or {"wind": False, "soil": False, "rain": False, "uv": False}
    sensor_health = compute_sensor_health(latest, enabled=enabled_groups)
    alerts = build_alerts(latest, sensor_health)
    conditions = build_conditions(latest)

    return MonitoringStatusResponse(
        device_id=latest.device_id,
        station_name=latest.station_name,
        last_updated=latest.recorded_at,
        overall_status=derive_overall_status(alerts),
        sensor_health=sensor_health,
        conditions=conditions,
        alerts=alerts,
        latest=latest,
    )


def build_trends(db: Session, device_id: str, hours: int) -> TrendsResponse | None:
    station = db.scalar(select(Station).where(Station.device_id == device_id))
    if not station:
        return None

    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    rows = db.execute(
        select(SensorReading)
        .where(SensorReading.station_id == station.id, SensorReading.recorded_at >= since)
        .order_by(SensorReading.recorded_at.asc())
    ).scalars().all()

    def point(timestamp: datetime, value: float | None) -> TrendPointResponse:
        return TrendPointResponse(timestamp=timestamp, value=value)

    return TrendsResponse(
        device_id=device_id,
        hours=hours,
        series={
            "moist": [point(row.recorded_at, row.soil_moisture) for row in rows],
            "temp": [point(row.recorded_at, row.soil_temperature) for row in rows],
            "rain": [point(row.recorded_at, row.rainfall) for row in rows],
            "ws": [point(row.recorded_at, row.wind_speed) for row in rows],
            "uv": [point(row.recorded_at, row.solar_radiation) for row in rows],
            "ec": [point(row.recorded_at, row.soil_ec) for row in rows],
            "ph": [point(row.recorded_at, row.soil_ph) for row in rows],
        },
    )


def build_station_admin_item(
    db: Session,
    station: Station,
    *,
    latest: ReadingResponse | None = None,
) -> AdminStationListItemResponse:
    latest_reading = latest or get_latest_reading(db, station.device_id)
    settings_row = ensure_station_settings(db, station, env=get_settings())

    overall_status = "offline"
    last_recorded_at = None
    last_received_at = None
    if latest_reading is not None:
        enabled_groups = get_enabled_sensor_groups(db, station.device_id) or {
            "wind": False,
            "soil": False,
            "rain": False,
            "uv": False,
        }
        sensor_health = compute_sensor_health(latest_reading, enabled=enabled_groups)
        alerts = build_alerts(latest_reading, sensor_health)
        overall_status = derive_overall_status(alerts)
        last_recorded_at = latest_reading.recorded_at
        last_received_at = latest_reading.received_at

    return AdminStationListItemResponse(
        device_id=station.device_id,
        station_name=station.name,
        created_at=station.created_at,
        updated_at=station.updated_at,
        last_recorded_at=last_recorded_at,
        last_received_at=last_received_at,
        overall_status=overall_status,
        settings_updated_at=settings_row.updated_at,
    )


def list_station_admin_items(db: Session) -> list[AdminStationListItemResponse]:
    stations = db.scalars(select(Station).order_by(Station.updated_at.desc(), Station.id.desc())).all()
    items = [build_station_admin_item(db, station) for station in stations]
    db.commit()
    return items


def build_station_admin_overview(db: Session, device_id: str) -> AdminStationOverviewResponse | None:
    station = db.scalar(select(Station).where(Station.device_id == device_id))
    if station is None:
        return None

    monitoring = build_monitoring_status(db, device_id)
    settings_response: StationSettingsResponse = fetch_station_settings(db, device_id)
    station = db.scalar(select(Station).where(Station.device_id == device_id))
    if station is None:
        return None

    summary_data = build_summary(db, device_id, 24)
    summary = StationSummaryResponse(**summary_data) if summary_data else None
    station_item = build_station_admin_item(
        db,
        station,
        latest=None if monitoring is None else monitoring.latest,
    )
    db.commit()

    return AdminStationOverviewResponse(
        station=station_item,
        monitoring=monitoring,
        settings=settings_response,
        summary=summary,
    )
