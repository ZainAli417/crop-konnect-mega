from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    app_name: str = Field(default="CropConnect Sensor Backend", alias="APP_NAME")
    app_env: str = Field(default="development", alias="APP_ENV")
    app_host: str = Field(default="0.0.0.0", alias="APP_HOST")
    app_port: int = Field(default=8000, alias="APP_PORT")
    database_url: str = Field(default="sqlite:///./cropconnect.db", alias="DATABASE_URL")
    ingest_api_key: str = Field(default="change-this-before-production", alias="INGEST_API_KEY")
    admin_api_key: str = Field(default="change-this-before-production", alias="ADMIN_API_KEY")
    cors_origins: str = Field(default="http://localhost:3000,http://localhost:5173", alias="CORS_ORIGINS")
    max_history_limit: int = Field(default=1000, alias="MAX_HISTORY_LIMIT")
    serial_reader_enabled: bool = Field(default=False, alias="SERIAL_READER_ENABLED")
    serial_poll_interval_seconds: int = Field(default=5, alias="SERIAL_POLL_INTERVAL_SECONDS")
    serial_startup_delay_seconds: int = Field(default=8, alias="SERIAL_STARTUP_DELAY_SECONDS")
    settings_refresh_interval_seconds: float = Field(default=1.0, alias="SETTINGS_REFRESH_INTERVAL_SECONDS")
    # How long cached station settings are reused before a cheap change-check.
    # This is what keeps the pollers from hammering the database; a settings
    # PATCH invalidates the cache immediately, so raising it costs nothing.
    settings_cache_ttl_seconds: float = Field(default=15.0, alias="SETTINGS_CACHE_TTL_SECONDS")

    # ── Sensor identity (see app/serial_ports.py) ─────────────────────────
    # Refuse to read a port whose sensor identity is not positively confirmed.
    # Publishing null beats publishing a UV value as rainfall.
    sensor_strict_identity: bool = Field(default=True, alias="SENSOR_STRICT_IDENTITY")
    # Probe adapters and match them against captured fingerprints, so identity
    # survives the hub re-enumerating and renaming /dev/ttyUSB*.
    sensor_fingerprint_enabled: bool = Field(default=True, alias="SENSOR_FINGERPRINT_ENABLED")
    sensor_signature_file: str = Field(default="sensor_signatures.json", alias="SENSOR_SIGNATURE_FILE")
    # Re-resolve identities periodically so a hot-plug is picked up without a
    # restart. 0 disables re-resolution after startup.
    sensor_identity_recheck_seconds: float = Field(default=300.0, alias="SENSOR_IDENTITY_RECHECK_SECONDS")
    # Hard ceiling on one sensor's blocking serial I/O. Exceeding it abandons
    # that sensor for the cycle instead of stalling the event loop.
    sensor_read_timeout_seconds: float = Field(default=6.0, alias="SENSOR_READ_TIMEOUT_SECONDS")
    # Consecutive failures before a sensor is put in backoff.
    sensor_failure_threshold: int = Field(default=3, alias="SENSOR_FAILURE_THRESHOLD")
    sensor_inter_read_delay_ms: int = Field(default=250, alias="SENSOR_INTER_READ_DELAY_MS")
    sensor_read_order: str = Field(
        default="wind_speed,wind_direction,soil,rain,solar",
        alias="SENSOR_READ_ORDER",
    )
    solar_read_retries: int = Field(default=2, alias="SOLAR_READ_RETRIES")
    serial_console_output_enabled: bool = Field(default=True, alias="SERIAL_CONSOLE_OUTPUT_ENABLED")
    excel_logging_enabled: bool = Field(default=True, alias="EXCEL_LOGGING_ENABLED")
    excel_log_dir: str = Field(default="reading_excel_logs", alias="EXCEL_LOG_DIR")
    excel_log_timezone: str = Field(default="Asia/Karachi", alias="EXCEL_LOG_TIMEZONE")
    device_id: str = Field(default="RPAWTEX", alias="DEVICE_ID")
    station_name: str = Field(default="Field Station 1", alias="STATION_NAME")
    gps_reader_enabled: bool = Field(default=False, alias="GPS_READER_ENABLED")
    gps_port: str = Field(default="/dev/ttyACM0", alias="GPS_PORT")
    gps_baud_rate: int = Field(default=9600, alias="GPS_BAUD_RATE")
    gps_min_move_meters: float = Field(default=5.0, alias="GPS_MIN_MOVE_METERS")
    gps_reverse_geocode_interval_seconds: int = Field(
        default=15,
        alias="GPS_REVERSE_GEOCODE_INTERVAL_SECONDS",
    )
    weather_forecast_enabled: bool = Field(default=False, alias="WEATHER_FORECAST_ENABLED")
    weather_forecast_provider: str = Field(default="open-meteo", alias="WEATHER_FORECAST_PROVIDER")
    weather_forecast_latitude: str | None = Field(default=None, alias="WEATHER_FORECAST_LATITUDE")
    weather_forecast_longitude: str | None = Field(default=None, alias="WEATHER_FORECAST_LONGITUDE")
    weather_forecast_hours: int = Field(default=24, alias="WEATHER_FORECAST_HOURS")
    weather_forecast_cache_minutes: int = Field(default=30, alias="WEATHER_FORECAST_CACHE_MINUTES")
    weather_forecast_timezone: str = Field(default="UTC", alias="WEATHER_FORECAST_TIMEZONE")
    wind_speed_port: str | None = Field(default=None, alias="WIND_SPEED_PORT")
    wind_direction_port: str | None = Field(default=None, alias="WIND_DIRECTION_PORT")
    soil_port: str | None = Field(default=None, alias="SOIL_PORT")
    rain_port: str | None = Field(default=None, alias="RAIN_PORT")
    solar_port: str | None = Field(default=None, alias="SOLAR_PORT")
    relay_control_enabled: bool = Field(default=False, alias="RELAY_CONTROL_ENABLED")
    relay_gpio_mode: str = Field(default="BCM", alias="RELAY_GPIO_MODE")
    relay_active_low: bool = Field(default=True, alias="RELAY_ACTIVE_LOW")
    relay_settle_seconds: float = Field(default=0.25, alias="RELAY_SETTLE_SECONDS")
    relay_wind_pin: int | None = Field(default=None, alias="RELAY_WIND_PIN")
    relay_soil_pin: int | None = Field(default=None, alias="RELAY_SOIL_PIN")
    relay_rain_pin: int | None = Field(default=None, alias="RELAY_RAIN_PIN")
    relay_solar_pin: int | None = Field(default=None, alias="RELAY_SOLAR_PIN")

    @property
    def allowed_origins(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def sensor_read_sequence(self) -> list[str]:
        return [sensor.strip() for sensor in self.sensor_read_order.split(",") if sensor.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
