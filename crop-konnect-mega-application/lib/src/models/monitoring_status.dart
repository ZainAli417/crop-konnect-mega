import 'sensor_reading.dart';

class MonitoringStatus {
  const MonitoringStatus({
    required this.deviceId,
    required this.stationName,
    required this.lastUpdated,
    required this.overallStatus,
    required this.sensorHealth,
    required this.conditions,
    required this.alerts,
    required this.latest,
  });

  final String deviceId;
  final String? stationName;
  final DateTime? lastUpdated;
  final String overallStatus;
  final Map<String, SensorHealth> sensorHealth;
  final Map<String, String> conditions;
  final List<MonitoringAlert> alerts;
  final SensorReading? latest;

  factory MonitoringStatus.fromJson(Map<String, dynamic> json) {
    final rawHealth = (json['sensor_health'] as Map<String, dynamic>? ?? <String, dynamic>{});
    final rawConditions = (json['conditions'] as Map<String, dynamic>? ?? <String, dynamic>{});
    final rawAlerts = (json['alerts'] as List<dynamic>? ?? <dynamic>[]);

    return MonitoringStatus(
      deviceId: json['device_id'] as String,
      stationName: json['station_name'] as String?,
      lastUpdated: json['last_updated'] == null
          ? null
          : DateTime.parse(json['last_updated'] as String).toLocal(),
      overallStatus: (json['overall_status'] as String? ?? 'unknown').toLowerCase(),
      sensorHealth: rawHealth.map(
        (key, value) => MapEntry(
          key,
          SensorHealth.fromJson(value as Map<String, dynamic>),
        ),
      ),
      conditions: rawConditions.map(
        (key, value) => MapEntry(key, (value as String? ?? 'unknown').toLowerCase()),
      ),
      alerts: rawAlerts
          .whereType<Map<String, dynamic>>()
          .map(MonitoringAlert.fromJson)
          .toList(),
      latest: json['latest'] is Map<String, dynamic>
          ? SensorReading.fromJson(json['latest'] as Map<String, dynamic>)
          : null,
    );
  }
}

class SensorHealth {
  const SensorHealth({
    required this.status,
    required this.freshness,
    required this.lastUpdated,
  });

  final String status;
  final String freshness;
  final DateTime? lastUpdated;

  factory SensorHealth.fromJson(Map<String, dynamic> json) {
    return SensorHealth(
      status: (json['status'] as String? ?? 'unknown').toLowerCase(),
      freshness: (json['freshness'] as String? ?? 'unknown').toLowerCase(),
      lastUpdated: json['last_updated'] == null
          ? null
          : DateTime.parse(json['last_updated'] as String).toLocal(),
    );
  }
}

class MonitoringAlert {
  const MonitoringAlert({
    required this.type,
    required this.severity,
    required this.title,
    required this.message,
    required this.timestamp,
  });

  final String type;
  final String severity;
  final String title;
  final String message;
  final DateTime? timestamp;

  factory MonitoringAlert.fromJson(Map<String, dynamic> json) {
    return MonitoringAlert(
      type: json['type'] as String? ?? 'unknown',
      severity: (json['severity'] as String? ?? 'info').toLowerCase(),
      title: json['title'] as String? ?? 'Alert',
      message: json['message'] as String? ?? '',
      timestamp: json['timestamp'] == null
          ? null
          : DateTime.parse(json['timestamp'] as String).toLocal(),
    );
  }
}
