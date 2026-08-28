enum AppDataMode {
  supabase,
  live,
  mock,
}

class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'CROPCONNECT_SENSOR_API_BASE_URL',
    defaultValue: 'https://earthscansystems.com/productdata/sensor',
  );
  static const String deviceId = String.fromEnvironment(
    'CROPCONNECT_SENSOR_DEVICE_ID',
    defaultValue: 'RPAWTEX',
  );
  static const String stationName = String.fromEnvironment(
    'CROPCONNECT_SENSOR_STATION_NAME',
    defaultValue: 'Field Station 1',
  );

  /// Base URL of the soil-weather advisory service (the DSS backend).
  /// Full endpoint: `$advisoryApiBaseUrl/advisory/api/advisory/soil-weather`.
  static const String advisoryApiBaseUrl = String.fromEnvironment(
    'CROPCONNECT_ADVISORY_API_BASE_URL',
    defaultValue: 'https://demo.escan-systems.com',
  );
  static const String supabaseUrl = String.fromEnvironment(
    'CROPCONNECT_SUPABASE_URL',
    defaultValue: 'https://oadsmdarmoxgauoqyhmd.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'CROPCONNECT_SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9hZHNtZGFybW94Z2F1b3F5aG1kIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3NjgyMDAsImV4cCI6MjA5MjM0NDIwMH0.7bOjNt1Ekjruu_4qFuAlcYYHSaS_uW7W6Huum4tKI8I',
  );
  static const AppDataMode defaultDataMode = AppDataMode.supabase;
  static const bool enableDataModeSwitcher = false;
  static const bool enableLiveWebsocket = bool.fromEnvironment(
    'CROPCONNECT_SENSOR_ENABLE_WEBSOCKET',
    defaultValue: false,
  );
  // ── Fallback weather location ─────────────────────────────────────────────
  // The station is solar powered and can be off-grid for days. Its site never
  // moves, so when no GPS row is available these coordinates are used to look
  // up substitute wind / rain / UV values.
  static const double defaultFieldLatitude = 30.1575;
  static const double defaultFieldLongitude = 71.5249;

  static const String _fieldLatitudeOverride =
      String.fromEnvironment('CROPCONNECT_FIELD_LATITUDE');
  static const String _fieldLongitudeOverride =
      String.fromEnvironment('CROPCONNECT_FIELD_LONGITUDE');

  static double get fieldLatitude =>
      double.tryParse(_fieldLatitudeOverride) ?? defaultFieldLatitude;
  static double get fieldLongitude =>
      double.tryParse(_fieldLongitudeOverride) ?? defaultFieldLongitude;

  /// How often the controller re-checks whether substitute weather is needed.
  static const Duration weatherFallbackCheckInterval = Duration(minutes: 15);

  static const Duration summaryRefreshInterval = Duration(seconds: 15);
  static const Duration monitoringRefreshInterval = Duration(seconds: 6);
  static const Duration trendsRefreshInterval = Duration(seconds: 15);
}
