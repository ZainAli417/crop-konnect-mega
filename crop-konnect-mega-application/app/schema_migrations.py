from __future__ import annotations

from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine


def ensure_runtime_schema(engine: Engine) -> None:
    inspector = inspect(engine)
    table_names = set(inspector.get_table_names())
    if "station_settings" in table_names:
        existing_columns = {
            column["name"]
            for column in inspector.get_columns("station_settings")
        }
        migrations: list[tuple[str, str]] = [
            (
                "sensor_read_schedule_json",
                "ALTER TABLE station_settings ADD COLUMN sensor_read_schedule_json TEXT NOT NULL DEFAULT '{}'",
            ),
            (
                "forecast_latitude",
                "ALTER TABLE station_settings ADD COLUMN forecast_latitude DOUBLE PRECISION NULL",
            ),
            (
                "forecast_longitude",
                "ALTER TABLE station_settings ADD COLUMN forecast_longitude DOUBLE PRECISION NULL",
            ),
        ]

        pending_sql = [
            statement
            for column_name, statement in migrations
            if column_name not in existing_columns
        ]
        if pending_sql:
            with engine.begin() as connection:
                for statement in pending_sql:
                    connection.execute(text(statement))
        if engine.dialect.name == "postgresql":
            default_off_columns = (
                "wind_speed_enabled",
                "wind_direction_enabled",
                "soil_enabled",
                "rain_enabled",
                "uv_enabled",
            )
            with engine.begin() as connection:
                for column in default_off_columns:
                    connection.execute(
                        text(
                            f"ALTER TABLE station_settings ALTER COLUMN {column} SET DEFAULT false"
                        )
                    )

    if "irrigation_profiles" in table_names:
        irrigation_profile_columns = {
            column["name"]
            for column in inspector.get_columns("irrigation_profiles")
        }
        profile_migrations: list[tuple[str, str]] = [
            (
                "smart_irrigation_enabled",
                "ALTER TABLE irrigation_profiles ADD COLUMN smart_irrigation_enabled BOOLEAN NOT NULL DEFAULT false",
            ),
        ]

        pending_profile_sql = [
            statement
            for column_name, statement in profile_migrations
            if column_name not in irrigation_profile_columns
        ]
        if pending_profile_sql:
            with engine.begin() as connection:
                for statement in pending_profile_sql:
                    connection.execute(text(statement))

    if "gps_readings" not in table_names:
        return

    existing_gps_columns = {
        column["name"]
        for column in inspector.get_columns("gps_readings")
    }
    gps_migrations: list[tuple[str, str]] = [
        (
            "received_at",
            "ALTER TABLE gps_readings ADD COLUMN received_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP",
        ),
        (
            "latitude",
            "ALTER TABLE gps_readings ADD COLUMN latitude DOUBLE PRECISION NULL",
        ),
        (
            "longitude",
            "ALTER TABLE gps_readings ADD COLUMN longitude DOUBLE PRECISION NULL",
        ),
        (
            "altitude_m",
            "ALTER TABLE gps_readings ADD COLUMN altitude_m DOUBLE PRECISION NULL",
        ),
        (
            "speed_kmh",
            "ALTER TABLE gps_readings ADD COLUMN speed_kmh DOUBLE PRECISION NULL",
        ),
        (
            "heading_deg",
            "ALTER TABLE gps_readings ADD COLUMN heading_deg DOUBLE PRECISION NULL",
        ),
        (
            "satellites",
            "ALTER TABLE gps_readings ADD COLUMN satellites VARCHAR(16) NULL",
        ),
        (
            "nmea_time",
            "ALTER TABLE gps_readings ADD COLUMN nmea_time VARCHAR(32) NULL",
        ),
        (
            "address",
            "ALTER TABLE gps_readings ADD COLUMN address VARCHAR(255) NULL",
        ),
        (
            "moved_meters",
            "ALTER TABLE gps_readings ADD COLUMN moved_meters DOUBLE PRECISION NULL",
        ),
    ]

    pending_gps_sql = [
        statement
        for column_name, statement in gps_migrations
        if column_name not in existing_gps_columns
    ]
    if pending_gps_sql:
        with engine.begin() as connection:
            for statement in pending_gps_sql:
                connection.execute(text(statement))
