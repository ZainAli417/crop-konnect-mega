from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, Float, ForeignKey, Index, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


class Station(Base):
    __tablename__ = "stations"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    device_id: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    readings: Mapped[list["SensorReading"]] = relationship(back_populates="station", cascade="all, delete-orphan")
    gps_readings: Mapped[list["GpsReading"]] = relationship(back_populates="station", cascade="all, delete-orphan")
    latest_reading: Mapped["LatestReading | None"] = relationship(
        back_populates="station", cascade="all, delete-orphan", uselist=False
    )
    settings: Mapped["StationSettings | None"] = relationship(
        back_populates="station", cascade="all, delete-orphan", uselist=False
    )
    irrigation_profile: Mapped["IrrigationProfile | None"] = relationship(
        back_populates="station", cascade="all, delete-orphan", uselist=False
    )
    irrigation_advisories: Mapped[list["IrrigationAdvisory"]] = relationship(
        back_populates="station", cascade="all, delete-orphan"
    )
    irrigation_actions: Mapped[list["IrrigationActionLog"]] = relationship(
        back_populates="station", cascade="all, delete-orphan"
    )


class StationSettings(Base):
    __tablename__ = "station_settings"
    __table_args__ = (
        UniqueConstraint("station_id", name="uq_station_settings_station_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    station_id: Mapped[int] = mapped_column(ForeignKey("stations.id", ondelete="CASCADE"), nullable=False, index=True)

    wind_speed_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="0")
    wind_direction_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="0")
    soil_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="0")
    rain_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="0")
    uv_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="0")

    forecast_latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    forecast_longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    poll_interval_seconds: Mapped[int] = mapped_column(Integer, nullable=False, server_default="5")
    inter_read_delay_ms: Mapped[int] = mapped_column(Integer, nullable=False, server_default="250")
    sensor_read_order: Mapped[str] = mapped_column(String(128), nullable=False, server_default="uv,wind_speed,wind_direction,soil,rain")
    sensor_read_schedule_json: Mapped[str] = mapped_column(Text, nullable=False, server_default="{}")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    station: Mapped["Station"] = relationship(back_populates="settings")


class IrrigationProfile(Base):
    __tablename__ = "irrigation_profiles"
    __table_args__ = (
        UniqueConstraint("station_id", name="uq_irrigation_profiles_station_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    station_id: Mapped[int] = mapped_column(ForeignKey("stations.id", ondelete="CASCADE"), nullable=False, index=True)

    field_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    crop: Mapped[str] = mapped_column(String(64), nullable=False, server_default="Rice")
    crop_stage: Mapped[str] = mapped_column(String(64), nullable=False, server_default="Vegetative")
    soil_type: Mapped[str] = mapped_column(String(64), nullable=False, server_default="Loam")
    irrigation_method: Mapped[str] = mapped_column(String(64), nullable=False, server_default="Flood")
    smart_irrigation_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")

    moisture_lower_target: Mapped[float] = mapped_column(Float, nullable=False, server_default="35")
    moisture_upper_target: Mapped[float] = mapped_column(Float, nullable=False, server_default="65")
    effective_rain_mm: Mapped[float] = mapped_column(Float, nullable=False, server_default="2")
    rain_window_hours: Mapped[int] = mapped_column(Integer, nullable=False, server_default="6")
    high_temp_c: Mapped[float] = mapped_column(Float, nullable=False, server_default="35")
    high_solar_wm2: Mapped[float] = mapped_column(Float, nullable=False, server_default="700")
    high_wind_ms: Mapped[float] = mapped_column(Float, nullable=False, server_default="6")
    stale_after_minutes: Mapped[int] = mapped_column(Integer, nullable=False, server_default="10")

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    station: Mapped["Station"] = relationship(back_populates="irrigation_profile")


class SensorReading(Base):
    __tablename__ = "sensor_readings"
    __table_args__ = (
        Index("ix_sensor_readings_station_recorded_at", "station_id", "recorded_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    station_id: Mapped[int] = mapped_column(ForeignKey("stations.id", ondelete="CASCADE"), nullable=False, index=True)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    wind_speed: Mapped[float | None] = mapped_column(Float, nullable=True)
    wind_direction_degrees: Mapped[float | None] = mapped_column(Float, nullable=True)
    wind_direction_label: Mapped[str | None] = mapped_column(String(8), nullable=True)
    soil_moisture: Mapped[float | None] = mapped_column(Float, nullable=True)
    soil_temperature: Mapped[float | None] = mapped_column(Float, nullable=True)
    soil_ec: Mapped[float | None] = mapped_column(Float, nullable=True)
    soil_nitrogen: Mapped[float | None] = mapped_column(Float, nullable=True)
    soil_phosphorus: Mapped[float | None] = mapped_column(Float, nullable=True)
    soil_potassium: Mapped[float | None] = mapped_column(Float, nullable=True)
    soil_ph: Mapped[float | None] = mapped_column(Float, nullable=True)
    rainfall: Mapped[float | None] = mapped_column(Float, nullable=True)
    solar_radiation: Mapped[float | None] = mapped_column(Float, nullable=True)

    station: Mapped["Station"] = relationship(back_populates="readings")
    irrigation_advisories: Mapped[list["IrrigationAdvisory"]] = relationship(back_populates="reading")


class GpsReading(Base):
    __tablename__ = "gps_readings"
    __table_args__ = (
        Index("ix_gps_readings_station_recorded_at", "station_id", "recorded_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    station_id: Mapped[int] = mapped_column(ForeignKey("stations.id", ondelete="CASCADE"), nullable=False, index=True)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    received_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    altitude_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    speed_kmh: Mapped[float | None] = mapped_column(Float, nullable=True)
    heading_deg: Mapped[float | None] = mapped_column(Float, nullable=True)
    satellites: Mapped[str | None] = mapped_column(String(16), nullable=True)
    nmea_time: Mapped[str | None] = mapped_column(String(32), nullable=True)
    address: Mapped[str | None] = mapped_column(String(255), nullable=True)
    moved_meters: Mapped[float | None] = mapped_column(Float, nullable=True)

    station: Mapped["Station"] = relationship(back_populates="gps_readings")


class LatestReading(Base):
    __tablename__ = "latest_readings"
    __table_args__ = (
        UniqueConstraint("station_id", name="uq_latest_readings_station_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    station_id: Mapped[int] = mapped_column(ForeignKey("stations.id", ondelete="CASCADE"), nullable=False, index=True)
    reading_id: Mapped[int] = mapped_column(ForeignKey("sensor_readings.id", ondelete="CASCADE"), nullable=False, unique=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    station: Mapped["Station"] = relationship(back_populates="latest_reading")


class IrrigationAdvisory(Base):
    __tablename__ = "irrigation_advisories"
    __table_args__ = (
        Index("ix_irrigation_advisories_station_generated_at", "station_id", "generated_at"),
        Index("ix_irrigation_advisories_station_decision", "station_id", "decision"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    station_id: Mapped[int] = mapped_column(ForeignKey("stations.id", ondelete="CASCADE"), nullable=False, index=True)
    reading_id: Mapped[int | None] = mapped_column(
        ForeignKey("sensor_readings.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    rule_version: Mapped[str] = mapped_column(String(32), nullable=False, server_default="irrigation-v1")
    generated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False, index=True)
    decision: Mapped[str] = mapped_column(String(48), nullable=False, index=True)
    urgency: Mapped[str] = mapped_column(String(24), nullable=False, index=True)
    data_status: Mapped[str] = mapped_column(String(24), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    condition_summary: Mapped[str] = mapped_column(Text, nullable=False)
    factors_json: Mapped[str] = mapped_column(Text, nullable=False)
    sensor_snapshot_json: Mapped[str] = mapped_column(Text, nullable=False)
    profile_snapshot_json: Mapped[str] = mapped_column(Text, nullable=False)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    station: Mapped["Station"] = relationship(back_populates="irrigation_advisories")
    reading: Mapped["SensorReading | None"] = relationship(back_populates="irrigation_advisories")
    actions: Mapped[list["IrrigationActionLog"]] = relationship(
        back_populates="advisory", cascade="all, delete-orphan"
    )


class IrrigationActionLog(Base):
    __tablename__ = "irrigation_action_logs"
    __table_args__ = (
        Index("ix_irrigation_action_logs_station_created_at", "station_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    station_id: Mapped[int] = mapped_column(ForeignKey("stations.id", ondelete="CASCADE"), nullable=False, index=True)
    advisory_id: Mapped[int | None] = mapped_column(
        ForeignKey("irrigation_advisories.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    action: Mapped[str] = mapped_column(String(48), nullable=False, index=True)
    actor_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    action_metadata_json: Mapped[str] = mapped_column(Text, nullable=False, server_default="{}")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    station: Mapped["Station"] = relationship(back_populates="irrigation_actions")
    advisory: Mapped["IrrigationAdvisory | None"] = relationship(back_populates="actions")
