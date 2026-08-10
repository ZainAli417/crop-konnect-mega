from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class ReadingPayload(BaseModel):
    ws: float | None = Field(default=None, description="Wind speed in m/s")
    wd_deg: float | None = Field(default=None, description="Wind direction in degrees")
    wd_dir: str | None = Field(default=None, description="Wind direction label")
    moist: float | None = Field(default=None, description="Soil moisture in percent")
    temp: float | None = Field(default=None, description="Soil temperature in C")
    ec: float | None = Field(default=None, description="Soil EC in uS/cm")
    n: float | None = Field(default=None, description="Soil nitrogen in mg/kg")
    p: float | None = Field(default=None, description="Soil phosphorus in mg/kg")
    k: float | None = Field(default=None, description="Soil potassium in mg/kg")
    ph: float | None = Field(default=None, description="Soil pH")
    rain: float | None = Field(default=None, description="Rainfall in mm")
    solar: float | None = Field(default=None, description="Solar radiation in W/m2")

    @field_validator("wd_dir")
    @classmethod
    def normalize_direction(cls, value: str | None) -> str | None:
        return value.upper() if value else value


class IngestRequest(BaseModel):
    device_id: str = Field(min_length=1, max_length=64)
    station_name: str | None = Field(default=None, max_length=128)
    recorded_at: datetime | None = Field(default=None, description="UTC ISO timestamp from device")
    data: ReadingPayload


class ReadingResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    device_id: str
    station_name: str | None = None
    recorded_at: datetime
    received_at: datetime
    ws: float | None = None
    wd_deg: float | None = None
    wd_dir: str | None = None
    moist: float | None = None
    temp: float | None = None
    ec: float | None = None
    n: float | None = None
    p: float | None = None
    k: float | None = None
    ph: float | None = None
    rain: float | None = None
    solar: float | None = None


class IngestResponse(BaseModel):
    message: str
    reading: ReadingResponse


class ReadingHistoryResponse(BaseModel):
    items: list[ReadingResponse]
    total: int
    limit: int


class GpsReadingResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    device_id: str
    station_name: str | None = None
    recorded_at: datetime
    received_at: datetime
    latitude: float | None = None
    longitude: float | None = None
    altitude_m: float | None = None
    speed_kmh: float | None = None
    heading_deg: float | None = None
    satellites: str | None = None
    nmea_time: str | None = None
    address: str | None = None
    moved_meters: float | None = None


class GpsReadingHistoryResponse(BaseModel):
    items: list[GpsReadingResponse]
    total: int
    limit: int


class StationSummaryResponse(BaseModel):
    device_id: str
    hours: int
    total_readings: int
    last_recorded_at: datetime | None = None
    averages: dict[str, float | None]


class SensorHealthResponse(BaseModel):
    status: str
    last_updated: datetime | None = None
    freshness: str


class AlertResponse(BaseModel):
    type: str
    severity: str
    title: str
    message: str
    timestamp: datetime | None = None


class MonitoringStatusResponse(BaseModel):
    device_id: str
    station_name: str | None = None
    last_updated: datetime | None = None
    overall_status: str
    sensor_health: dict[str, SensorHealthResponse]
    conditions: dict[str, str]
    alerts: list[AlertResponse]
    latest: ReadingResponse | None = None


class TrendPointResponse(BaseModel):
    timestamp: datetime
    value: float | None = None


class TrendsResponse(BaseModel):
    device_id: str
    hours: int
    series: dict[str, list[TrendPointResponse]]


class SensorToggleResponse(BaseModel):
    enabled: bool


class SensorTogglePatch(BaseModel):
    model_config = ConfigDict(extra="ignore")

    enabled: bool | None = None


class StationSensorsSettingsResponse(BaseModel):
    wind_speed: SensorToggleResponse
    wind_direction: SensorToggleResponse
    soil: SensorToggleResponse
    rain: SensorToggleResponse
    uv: SensorToggleResponse


class StationSensorsSettingsPatch(BaseModel):
    model_config = ConfigDict(extra="ignore")

    wind_speed: SensorTogglePatch | None = None
    wind_direction: SensorTogglePatch | None = None
    soil: SensorTogglePatch | None = None
    rain: SensorTogglePatch | None = None
    uv: SensorTogglePatch | None = None


class SensorCadenceResponse(BaseModel):
    enabled: bool
    mode: str
    reads_per_day: int | None = None
    interval_seconds: int | None = None
    priority: int | None = None


class SensorCadencePatch(BaseModel):
    model_config = ConfigDict(extra="ignore")

    mode: str | None = None
    reads_per_day: int | None = None
    priority: int | None = None


class StationSensorScheduleResponse(BaseModel):
    items: dict[str, SensorCadenceResponse]


class StationSensorSchedulePatch(BaseModel):
    model_config = ConfigDict(extra="ignore")

    items: dict[str, SensorCadencePatch] | None = None


class StationForecastSettingsResponse(BaseModel):
    latitude: float | None = None
    longitude: float | None = None


class StationForecastSettingsPatch(BaseModel):
    model_config = ConfigDict(extra="ignore")

    latitude: float | None = None
    longitude: float | None = None


class StationPollingSettingsResponse(BaseModel):
    poll_interval_seconds: int
    inter_read_delay_ms: int
    sensor_read_order: list[str]
    sensor_schedule: StationSensorScheduleResponse


class StationPollingSettingsPatch(BaseModel):
    model_config = ConfigDict(extra="ignore")

    poll_interval_seconds: int | None = None
    inter_read_delay_ms: int | None = None
    sensor_read_order: list[str] | None = None
    sensor_schedule: StationSensorSchedulePatch | None = None


class StationRuntimeSettingsResponse(BaseModel):
    forecast: StationForecastSettingsResponse


class StationRuntimeSettingsPatch(BaseModel):
    forecast: StationForecastSettingsPatch | None = None


class StationSettingsResponse(BaseModel):
    device_id: str
    station_name: str | None = None
    sensors: StationSensorsSettingsResponse
    polling: StationPollingSettingsResponse
    runtime: StationRuntimeSettingsResponse
    updated_at: datetime | None = None


class StationSettingsUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    sensors: StationSensorsSettingsPatch | None = None
    polling: StationPollingSettingsPatch | None = None
    runtime: StationRuntimeSettingsPatch | None = None


class IrrigationProfileResponse(BaseModel):
    id: int
    device_id: str
    station_name: str | None = None
    field_name: str | None = None
    crop: str
    crop_stage: str
    soil_type: str
    irrigation_method: str
    smart_irrigation_enabled: bool
    moisture_lower_target: float
    moisture_upper_target: float
    effective_rain_mm: float
    rain_window_hours: int
    high_temp_c: float
    high_solar_wm2: float
    high_wind_ms: float
    stale_after_minutes: int
    created_at: datetime
    updated_at: datetime


class IrrigationProfileUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    crop: str | None = Field(default=None, min_length=1, max_length=64)
    crop_stage: str | None = Field(default=None, min_length=1, max_length=64)
    smart_irrigation_enabled: bool | None = None
    field_name: str | None = Field(default=None, max_length=128)
    soil_type: str | None = Field(default=None, max_length=64)
    irrigation_method: str | None = Field(default=None, max_length=64)
    moisture_lower_target: float | None = None
    moisture_upper_target: float | None = None
    effective_rain_mm: float | None = None
    rain_window_hours: int | None = None
    high_temp_c: float | None = None
    high_solar_wm2: float | None = None
    high_wind_ms: float | None = None
    stale_after_minutes: int | None = None


class IrrigationPresetStageResponse(BaseModel):
    stage: str
    moisture_lower_target: float
    moisture_upper_target: float
    effective_rain_mm: float
    rain_window_hours: int
    high_temp_c: float
    high_solar_wm2: float
    high_wind_ms: float
    stale_after_minutes: int


class IrrigationCropOptionResponse(BaseModel):
    crop: str
    stages: list[IrrigationPresetStageResponse]


class IrrigationPresetListResponse(BaseModel):
    items: list[IrrigationCropOptionResponse]


class IrrigationAdvisoryResponse(BaseModel):
    id: int
    device_id: str
    station_name: str | None = None
    reading_id: int | None = None
    rule_version: str
    generated_at: datetime
    decision: str
    urgency: str
    data_status: str
    title: str
    message: str
    reason: str
    condition_summary: str
    factors: dict[str, object]
    sensor_snapshot: dict[str, object]
    profile_snapshot: dict[str, object]


class IrrigationAdvisoryHistoryResponse(BaseModel):
    items: list[IrrigationAdvisoryResponse]
    total: int
    limit: int


class IrrigationActionRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    advisory_id: int | None = None
    action: str = Field(min_length=1, max_length=48)
    actor_id: str | None = Field(default=None, max_length=128)
    note: str | None = Field(default=None, max_length=1000)
    metadata: dict[str, object] = Field(default_factory=dict)

    @field_validator("action")
    @classmethod
    def normalize_action(cls, value: str) -> str:
        return value.strip().lower()


class IrrigationActionResponse(BaseModel):
    id: int
    device_id: str
    advisory_id: int | None = None
    action: str
    actor_id: str | None = None
    note: str | None = None
    metadata: dict[str, object]
    created_at: datetime


class AdminStationListItemResponse(BaseModel):
    device_id: str
    station_name: str | None = None
    created_at: datetime
    updated_at: datetime
    last_recorded_at: datetime | None = None
    last_received_at: datetime | None = None
    overall_status: str
    settings_updated_at: datetime | None = None


class AdminStationListResponse(BaseModel):
    items: list[AdminStationListItemResponse]


class AdminStationOverviewResponse(BaseModel):
    station: AdminStationListItemResponse
    monitoring: MonitoringStatusResponse | None = None
    settings: StationSettingsResponse
    summary: StationSummaryResponse | None = None
