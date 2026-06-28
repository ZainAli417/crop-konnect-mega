class StationSummary {
  const StationSummary({
    required this.deviceId,
    required this.hours,
    required this.totalReadings,
    required this.lastRecordedAt,
    required this.averages,
  });

  final String deviceId;
  final int hours;
  final int totalReadings;
  final DateTime? lastRecordedAt;
  final Map<String, double?> averages;

  factory StationSummary.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic value) {
      if (value == null) {
        return null;
      }
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value.toString());
    }

    final rawAverages = (json['averages'] as Map<String, dynamic>? ?? <String, dynamic>{});

    return StationSummary(
      deviceId: json['device_id'] as String,
      hours: json['hours'] as int,
      totalReadings: json['total_readings'] as int,
      lastRecordedAt: json['last_recorded_at'] == null
          ? null
          : DateTime.parse(json['last_recorded_at'] as String).toLocal(),
      averages: rawAverages.map((key, value) => MapEntry(key, asDouble(value))),
    );
  }
}
