import '../models/monitoring_status.dart';
import '../models/sensor_reading.dart';
import '../models/station_settings.dart';

/// Derives a [MonitoringStatus] — conditions, sensor health, alerts and the
/// overall roll-up — from a single reading.
///
/// This lives on its own because two callers need the *same* rules: the cloud
/// data source builds the status from the row the station wrote, and the
/// dashboard rebuilds it whenever the station's weather block has been
/// substituted. Sharing one implementation is what keeps a chip, a health row
/// and an alert saying the same thing regardless of which set of numbers is
/// behind them.
class StationStatusBuilder {
  const StationStatusBuilder();

  /// A reading older than this marks its sensors stale.
  static const Duration freshnessWindow = Duration(minutes: 10);

  /// The sensor groups the health map reports on.
  static const List<String> sensorKeys = <String>['wind', 'soil', 'rain', 'uv'];

  MonitoringStatus build({
    required SensorReading reading,
    required Map<String, bool> enabled,
    DateTime? now,
  }) {
    final conditions = buildConditions(reading);
    final health = buildSensorHealth(reading, enabled: enabled, now: now);
    final alerts = buildAlerts(reading, health, conditions);

    return MonitoringStatus(
      deviceId: reading.deviceId,
      stationName: reading.stationName,
      lastUpdated: reading.recordedAt,
      overallStatus: overallStatus(alerts),
      sensorHealth: health,
      conditions: conditions,
      alerts: alerts,
      latest: reading,
    );
  }

  Map<String, String> buildConditions(SensorReading reading) {
    return <String, String>{
      'soil_moisture': reading.moist == null
          ? 'unknown'
          : reading.moist! < 20
              ? 'low'
              : reading.moist! > 60
                  ? 'high'
                  : 'normal',
      'temperature': reading.temp == null
          ? 'unknown'
          : reading.temp! > 35
              ? 'hot'
              : reading.temp! < 15
                  ? 'cool'
                  : 'normal',
      'rain': reading.rain != null && reading.rain! > 0
          ? 'detected'
          : 'not_detected',
      'wind': reading.ws == null
          ? 'unknown'
          : reading.ws! > 10
              ? 'high'
              : reading.ws! > 5
                  ? 'moderate'
                  : 'calm',
      'uv': reading.solar == null
          ? 'unknown'
          : reading.solar! > 700
              ? 'high'
              : reading.solar! > 300
                  ? 'moderate'
                  : 'low',
      'ec': reading.ec == null
          ? 'unknown'
          : reading.ec! > 1800
              ? 'high'
              : 'normal',
    };
  }

  /// Freshness is read off [reading] itself, so a sensor is healthy exactly
  /// when the values being shown for it are current.
  Map<String, SensorHealth> buildSensorHealth(
    SensorReading reading, {
    required Map<String, bool> enabled,
    DateTime? now,
  }) {
    final isStale = (now ?? DateTime.now())
            .difference(reading.recordedAt)
            .compareTo(freshnessWindow) >
        0;

    SensorHealth health(bool isEnabled) {
      if (!isEnabled) {
        return const SensorHealth(
          status: 'disabled',
          freshness: 'disabled',
          lastUpdated: null,
        );
      }
      return SensorHealth(
        status: isStale ? 'stale' : 'online',
        freshness: isStale ? 'stale' : 'fresh',
        lastUpdated: reading.recordedAt,
      );
    }

    return <String, SensorHealth>{
      for (final key in sensorKeys) key: health(enabled[key] ?? false),
    };
  }

  List<MonitoringAlert> buildAlerts(
    SensorReading reading,
    Map<String, SensorHealth> health,
    Map<String, String> conditions,
  ) {
    final alerts = <MonitoringAlert>[];

    if (health.values.any((item) => item.freshness == 'stale')) {
      alerts.add(
        MonitoringAlert(
          type: 'stale_data',
          severity: 'warning',
          title: 'Data delay detected',
          message: 'Latest cloud reading is older than the freshness window.',
          timestamp: reading.recordedAt,
        ),
      );
    }
    if (conditions['soil_moisture'] == 'low') {
      alerts.add(
        MonitoringAlert(
          type: 'low_moisture',
          severity: 'warning',
          title: 'Low soil moisture',
          message: 'Soil moisture is below the basic monitoring threshold.',
          timestamp: reading.recordedAt,
        ),
      );
    }
    if (conditions['temperature'] == 'hot') {
      alerts.add(
        MonitoringAlert(
          type: 'high_temperature',
          severity: 'warning',
          title: 'High soil temperature',
          message: 'Soil temperature is elevated and may increase crop stress.',
          timestamp: reading.recordedAt,
        ),
      );
    }
    if (conditions['rain'] == 'detected') {
      alerts.add(
        MonitoringAlert(
          type: 'rain_detected',
          severity: 'info',
          title: 'Rain detected',
          message: 'Rainfall is present in the latest cloud reading.',
          timestamp: reading.recordedAt,
        ),
      );
    }
    if (conditions['wind'] == 'high') {
      alerts.add(
        MonitoringAlert(
          type: 'high_wind',
          severity: 'warning',
          title: 'High wind speed',
          message: 'Wind speed is high and should be watched for operations.',
          timestamp: reading.recordedAt,
        ),
      );
    }
    return alerts;
  }

  String overallStatus(List<MonitoringAlert> alerts) {
    if (alerts.any((alert) => alert.severity == 'critical')) return 'critical';
    if (alerts.any((alert) => alert.severity == 'warning')) return 'attention';
    return 'normal';
  }

  /// Which sensor groups the station has switched on.
  static Map<String, bool> enabledFromSettings(StationSettings? settings) {
    final sensors = settings?.sensors;
    return <String, bool>{
      'wind': (sensors?.windSpeedEnabled ?? false) ||
          (sensors?.windDirectionEnabled ?? false),
      'soil': sensors?.soilEnabled ?? false,
      'rain': sensors?.rainEnabled ?? false,
      'uv': sensors?.uvEnabled ?? false,
    };
  }

  /// Recover the enablement flags from a status that was already built, for
  /// when a rebuild happens without the settings on hand.
  static Map<String, bool> enabledFromHealth(Map<String, SensorHealth> health) {
    return <String, bool>{
      for (final key in sensorKeys)
        key: (health[key]?.status ?? 'disabled') != 'disabled',
    };
  }
}
