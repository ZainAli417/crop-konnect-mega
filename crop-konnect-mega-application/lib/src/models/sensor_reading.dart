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
    this.airTempC,
    this.humidityPct,
    this.uvIndex,
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

  // ── Values the station has no sensor for ──────────────────────────────────
  // Null for anything the logger produced; populated only when the weather
  // block is standing in for a station that has gone dark.
  final double? airTempC;
  final double? humidityPct;
  final double? uvIndex;

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
      airTempC: asDouble(json['air_temperature'] ?? json['temperature_2m']),
      humidityPct: asDouble(json['humidity'] ?? json['relative_humidity']),
      uvIndex: asDouble(json['uv_index']),
    );
  }

  /// Copy with selected fields replaced. Passing null for a field keeps the
  /// current value, so a caller only has to name what it is actually changing.
  SensorReading copyWith({
    DateTime? recordedAt,
    DateTime? receivedAt,
    double? ws,
    double? wdDeg,
    String? wdDir,
    double? moist,
    double? temp,
    double? ec,
    double? n,
    double? p,
    double? k,
    double? ph,
    double? rain,
    double? solar,
    double? airTempC,
    double? humidityPct,
    double? uvIndex,
  }) {
    return SensorReading(
      id: id,
      deviceId: deviceId,
      stationName: stationName,
      recordedAt: recordedAt ?? this.recordedAt,
      receivedAt: receivedAt ?? this.receivedAt,
      ws: ws ?? this.ws,
      wdDeg: wdDeg ?? this.wdDeg,
      wdDir: wdDir ?? this.wdDir,
      moist: moist ?? this.moist,
      temp: temp ?? this.temp,
      ec: ec ?? this.ec,
      n: n ?? this.n,
      p: p ?? this.p,
      k: k ?? this.k,
      ph: ph ?? this.ph,
      rain: rain ?? this.rain,
      solar: solar ?? this.solar,
      airTempC: airTempC ?? this.airTempC,
      humidityPct: humidityPct ?? this.humidityPct,
      uvIndex: uvIndex ?? this.uvIndex,
    );
  }
}
