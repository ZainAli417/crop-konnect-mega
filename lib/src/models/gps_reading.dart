class GpsReading {
  const GpsReading({
    required this.id,
    required this.stationId,
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
    this.altitudeM,
    this.speedKmh,
    this.headingDeg,
    this.satellites,
    this.address,
  });

  final int id;
  final int stationId;
  final DateTime recordedAt;
  final double? latitude;
  final double? longitude;
  final double? altitudeM;
  final double? speedKmh;
  final double? headingDeg;
  final String? satellites;
  final String? address;

  factory GpsReading.fromJson(Map<String, dynamic> json) {
    return GpsReading(
      id: (json['id'] as num).toInt(),
      stationId: (json['station_id'] as num).toInt(),
      recordedAt: DateTime.parse(json['recorded_at'] as String).toLocal(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      altitudeM: (json['altitude_m'] as num?)?.toDouble(),
      speedKmh: (json['speed_kmh'] as num?)?.toDouble(),
      headingDeg: (json['heading_deg'] as num?)?.toDouble(),
      satellites: json['satellites'] as String?,
      address: json['address'] as String?,
    );
  }
}
