class SensorReading {
  const SensorReading({
    required this.id,
    required this.deviceId,
    required this.stationName,
    required this.recordedAt,
    required this.receivedAt,
    required this.ws,
    required this.wdDeg,
    required this.wdDir,
    required this.moist,
    required this.temp,
    required this.ec,
    required this.n,
    required this.p,
    required this.k,
    required this.ph,
    required this.rain,
    required this.solar,
  });

  final int id;
  final String deviceId;
  final String? stationName;
  final DateTime recordedAt;
  final DateTime receivedAt;
  final double? ws;
  final double? wdDeg;
  final String? wdDir;
  final double? moist;
  final double? temp;
  final double? ec;
  final double? n;
  final double? p;
  final double? k;
  final double? ph;
  final double? rain;
  final double? solar;

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic value) {
      if (value == null) {
        return null;
      }
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value.toString());
    }

    return SensorReading(
      id: json['id'] as int,
      deviceId: json['device_id'] as String,
      stationName: json['station_name'] as String?,
      recordedAt: DateTime.parse(json['recorded_at'] as String).toLocal(),
      receivedAt: DateTime.parse(json['received_at'] as String).toLocal(),
      ws: asDouble(json['ws'] ?? json['wind_speed']),
      wdDeg: asDouble(json['wd_deg'] ?? json['wind_direction_degrees']),
      wdDir: (json['wd_dir'] ?? json['wind_direction_label']) as String?,
      moist: asDouble(json['moist'] ?? json['soil_moisture']),
      temp: asDouble(json['temp'] ?? json['soil_temperature']),
      ec: asDouble(json['ec'] ?? json['soil_ec']),
      n: asDouble(json['n'] ?? json['soil_nitrogen']),
      p: asDouble(json['p'] ?? json['soil_phosphorus']),
      k: asDouble(json['k'] ?? json['soil_potassium']),
      ph: asDouble(json['ph'] ?? json['soil_ph']),
      rain: asDouble(json['rain'] ?? json['rainfall']),
      solar: asDouble(json['solar'] ?? json['solar_radiation']),
    );
  }
}
