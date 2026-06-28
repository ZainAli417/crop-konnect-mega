class StationTrends {
  const StationTrends({
    required this.deviceId,
    required this.hours,
    required this.series,
  });

  final String deviceId;
  final int hours;
  final Map<String, List<TrendPoint>> series;

  factory StationTrends.fromJson(Map<String, dynamic> json) {
    final rawSeries = (json['series'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return StationTrends(
      deviceId: json['device_id'] as String,
      hours: json['hours'] as int,
      series: rawSeries.map(
        (key, value) => MapEntry(
          key,
          (value as List<dynamic>? ?? <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(TrendPoint.fromJson)
              .toList(),
        ),
      ),
    );
  }
}

class TrendPoint {
  const TrendPoint({
    required this.timestamp,
    required this.value,
  });

  final DateTime timestamp;
  final double? value;

  factory TrendPoint.fromJson(Map<String, dynamic> json) {
    return TrendPoint(
      timestamp: DateTime.parse(json['timestamp'] as String).toLocal(),
      value: _asDouble(json['value']),
    );
  }

  static double? _asDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}
