import asyncio
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import Depends, FastAPI, Header, HTTPException, Query, WebSocket, WebSocketDisconnect, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session

from app.config import get_settings
from app.db import Base, SessionLocal, engine, get_db
from app.excel_logger import ensure_today_excel_log
from app.schemas import (
    AdminStationListResponse,
    AdminStationOverviewResponse,
    IngestRequest,
    IngestResponse,
    GpsReadingHistoryResponse,
    GpsReadingResponse,
    IrrigationActionRequest,
    IrrigationActionResponse,
    IrrigationAdvisoryHistoryResponse,
    IrrigationAdvisoryResponse,
    IrrigationPresetListResponse,
    IrrigationProfileResponse,
    IrrigationProfileUpdateRequest,
    MonitoringStatusResponse,
    ReadingHistoryResponse,
    StationSummaryResponse,
    StationSettingsResponse,
    StationSettingsUpdateRequest,
    TrendsResponse,
)
from app.schema_migrations import ensure_runtime_schema
from app.settings_cache import get_settings_cache
from app.gps_runtime import GpsTracker
from app.sensor_runtime import SerialSensorPoller
from app.solar_runtime import SolarReadingCache, SolarSensorPoller
from app.irrigation import (
    create_irrigation_action,
    fetch_irrigation_profile,
    get_latest_irrigation_advisory,
    list_irrigation_presets,
    list_irrigation_advisories,
    patch_irrigation_profile,
)
from app.services import (
    build_station_admin_overview,
    build_monitoring_status,
    build_summary,
    build_trends,
    clamp_limit,
    create_reading,
    get_latest_gps_fix,
    get_latest_reading,
    get_or_create_station,
    list_gps_fixes,
    list_station_admin_items,
    list_readings,
    live_manager,
)
from app.station_settings import fetch_station_settings, patch_station_settings


settings = get_settings()
solar_cache = SolarReadingCache()
serial_poller = SerialSensorPoller(settings, solar_cache)
# Share the sensor poller's resolver so both agree on which adapter is solar.
solar_poller = SolarSensorPoller(settings, solar_cache, serial_poller.port_resolver)
gps_tracker = GpsTracker(settings)


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    ensure_runtime_schema(engine)
    ensure_today_excel_log(settings)
    db = SessionLocal()
    try:
        get_or_create_station(db, settings.device_id, settings.station_name)
        db.commit()
        fetch_station_settings(db, settings.device_id, settings.station_name, env=settings)
    finally:
        db.close()
    # Resolve which USB adapter is which before either poller reads, so no cycle
    # can publish a value under the wrong sensor's name. Probing is blocking.
    if settings.serial_reader_enabled:
        await asyncio.to_thread(serial_poller.resolve_identities, reason="startup")
    await solar_poller.start()
    await serial_poller.start()
    await gps_tracker.start()
    yield
    await gps_tracker.stop()
    await serial_poller.stop()
    await solar_poller.stop()


app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins or ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def verify_api_key(x_api_key: str = Header(default="")) -> None:
    if x_api_key != settings.ingest_api_key:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API key")


def verify_admin_api_key(x_admin_key: str = Header(default="")) -> None:
    if x_admin_key != settings.admin_api_key:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid admin API key")


@app.get("/health")
def healthcheck() -> dict:
    return {
        "status": "ok",
        "environment": settings.app_env,
        "serial_reader": serial_poller.status(),
        "gps_reader": gps_tracker.status(),
    }


@app.get("/api/v1/runtime/serial")
def fetch_serial_runtime() -> dict:
    return serial_poller.status()


@app.get("/api/v1/runtime/gps")
def fetch_gps_runtime() -> dict:
    return gps_tracker.status()


@app.get("/api/v1/runtime/solar")
def fetch_solar_runtime() -> dict:
    return solar_poller.status()


@app.post("/api/v1/ingest/readings", response_model=IngestResponse, status_code=status.HTTP_201_CREATED)
async def ingest_reading(
    payload: IngestRequest,
    _: None = Depends(verify_api_key),
    db: Session = Depends(get_db),
):
    reading = create_reading(db, payload)
    await live_manager.broadcast(payload.device_id, {"type": "reading.created", "payload": reading.model_dump(mode="json")})
    advisory = get_latest_irrigation_advisory(db, payload.device_id, regenerate=False)
    if advisory is not None:
        await live_manager.broadcast(
            payload.device_id,
            {"type": "irrigation.advisory.updated", "payload": advisory.model_dump(mode="json")},
    )
    return IngestResponse(message="Reading ingested successfully", reading=reading)


@app.get("/api/v1/stations/{device_id}/latest")
def fetch_latest_reading(device_id: str, db: Session = Depends(get_db)):
    reading = get_latest_reading(db, device_id)
    if not reading:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No readings found for this device")
    return reading


@app.get("/api/v1/stations/{device_id}/gps/latest", response_model=GpsReadingResponse)
def fetch_latest_gps_fix_endpoint(device_id: str, db: Session = Depends(get_db)):
    reading = get_latest_gps_fix(db, device_id)
    if not reading:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No GPS fix found for this device")
    return reading


@app.get("/api/v1/stations/{device_id}/gps/readings", response_model=GpsReadingHistoryResponse)
def fetch_gps_history_endpoint(
    device_id: str,
    limit: int = Query(default=100, ge=1),
    db: Session = Depends(get_db),
):
    safe_limit = clamp_limit(limit)
    items, total = list_gps_fixes(db, device_id, safe_limit)
    return GpsReadingHistoryResponse(items=items, total=total, limit=safe_limit)


@app.get("/api/v1/stations/{device_id}/readings", response_model=ReadingHistoryResponse)
def fetch_reading_history(
    device_id: str,
    limit: int = Query(default=100, ge=1),
    recorded_from: datetime | None = Query(default=None),
    recorded_to: datetime | None = Query(default=None),
    db: Session = Depends(get_db),
):
    safe_limit = clamp_limit(limit)
    items, total = list_readings(db, device_id, safe_limit, recorded_from, recorded_to)
    return ReadingHistoryResponse(items=items, total=total, limit=safe_limit)


@app.get("/api/v1/stations/{device_id}/summary", response_model=StationSummaryResponse)
def fetch_station_summary(
    device_id: str,
    hours: int = Query(default=24, ge=1, le=720),
    db: Session = Depends(get_db),
):
    summary = build_summary(db, device_id, hours)
    if not summary:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Station not found")
    return StationSummaryResponse(**summary)


@app.get("/api/v1/stations/{device_id}/monitoring-status", response_model=MonitoringStatusResponse)
def fetch_monitoring_status(device_id: str, db: Session = Depends(get_db)):
    monitoring = build_monitoring_status(db, device_id)
    if not monitoring:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Station not found")
    return monitoring


@app.get("/api/v1/stations/{device_id}/trends", response_model=TrendsResponse)
def fetch_station_trends(
    device_id: str,
    hours: int = Query(default=24, ge=1, le=168),
    db: Session = Depends(get_db),
):
    trends = build_trends(db, device_id, hours)
    if not trends:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Station not found")
    return trends


@app.get("/api/v1/stations/{device_id}/settings", response_model=StationSettingsResponse)
def fetch_station_settings_endpoint(device_id: str, db: Session = Depends(get_db)):
    return fetch_station_settings(db, device_id)


@app.patch("/api/v1/stations/{device_id}/settings", response_model=StationSettingsResponse)
async def update_station_settings_endpoint(
    device_id: str,
    payload: StationSettingsUpdateRequest,
    db: Session = Depends(get_db),
):
    updated = patch_station_settings(db, device_id, payload)
    # The pollers read settings through a TTL cache; invalidate so a toggle in
    # the app takes effect on the next cycle instead of after the TTL.
    if device_id == settings.device_id:
        get_settings_cache(settings).invalidate()
    await live_manager.broadcast(
        device_id,
        {"type": "settings.updated", "payload": updated.model_dump(mode="json")},
    )
    return updated


@app.get("/api/v1/irrigation/presets", response_model=IrrigationPresetListResponse)
def fetch_irrigation_presets_endpoint():
    return list_irrigation_presets()


@app.get("/api/v1/stations/{device_id}/irrigation/profile", response_model=IrrigationProfileResponse)
def fetch_irrigation_profile_endpoint(device_id: str, db: Session = Depends(get_db)):
    return fetch_irrigation_profile(db, device_id)


@app.patch("/api/v1/stations/{device_id}/irrigation/profile", response_model=IrrigationProfileResponse)
def update_irrigation_profile_endpoint(
    device_id: str,
    payload: IrrigationProfileUpdateRequest,
    db: Session = Depends(get_db),
):
    try:
        return patch_irrigation_profile(db, device_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@app.get("/api/v1/stations/{device_id}/irrigation/advisory/latest", response_model=IrrigationAdvisoryResponse)
def fetch_latest_irrigation_advisory_endpoint(device_id: str, db: Session = Depends(get_db)):
    advisory = get_latest_irrigation_advisory(db, device_id)
    if advisory is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No irrigation advisory found for this device")
    return advisory


@app.get("/api/v1/stations/{device_id}/irrigation/advisory/history", response_model=IrrigationAdvisoryHistoryResponse)
def fetch_irrigation_advisory_history_endpoint(
    device_id: str,
    limit: int = Query(default=100, ge=1),
    db: Session = Depends(get_db),
):
    safe_limit = clamp_limit(limit)
    items, total = list_irrigation_advisories(db, device_id, limit=safe_limit)
    return IrrigationAdvisoryHistoryResponse(items=items, total=total, limit=safe_limit)


@app.post("/api/v1/stations/{device_id}/irrigation/actions", response_model=IrrigationActionResponse)
def create_irrigation_action_endpoint(
    device_id: str,
    payload: IrrigationActionRequest,
    db: Session = Depends(get_db),
):
    try:
        return create_irrigation_action(db, device_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@app.get("/api/v1/admin/stations", response_model=AdminStationListResponse)
def list_admin_stations(
    _: None = Depends(verify_admin_api_key),
    db: Session = Depends(get_db),
):
    return AdminStationListResponse(items=list_station_admin_items(db))


@app.get("/api/v1/admin/stations/{device_id}/overview", response_model=AdminStationOverviewResponse)
def fetch_admin_station_overview(
    device_id: str,
    _: None = Depends(verify_admin_api_key),
    db: Session = Depends(get_db),
):
    overview = build_station_admin_overview(db, device_id)
    if overview is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Station not found")
    return overview


@app.patch("/api/v1/admin/stations/{device_id}/settings", response_model=StationSettingsResponse)
async def update_admin_station_settings(
    device_id: str,
    payload: StationSettingsUpdateRequest,
    _: None = Depends(verify_admin_api_key),
    db: Session = Depends(get_db),
):
    updated = patch_station_settings(db, device_id, payload)
    # The pollers read settings through a TTL cache; invalidate so a toggle in
    # the app takes effect on the next cycle instead of after the TTL.
    if device_id == settings.device_id:
        get_settings_cache(settings).invalidate()
    await live_manager.broadcast(
        device_id,
        {"type": "settings.updated", "payload": updated.model_dump(mode="json")},
    )
    return updated


@app.websocket("/ws/stations/{device_id}")
async def station_stream(device_id: str, websocket: WebSocket):
    await live_manager.connect(device_id, websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        live_manager.disconnect(device_id, websocket)
