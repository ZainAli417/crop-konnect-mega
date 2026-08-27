import 'package:uuid/uuid.dart';

/// A soil sample captured with the C-type RS-485 probe.
///
/// Ported from Crop Konnect UNO's `SoilData` model — the field set, the
/// `soil_samples` column mapping and the lenient parsing are kept as they were
/// so rows written by either app stay readable by both. The one addition is
/// [farmId], which records the farm each sample was taken on.
class SoilSample {
  SoilSample({
    String? id,
    DateTime? timestamp,
    this.lat = 0.0,
    this.lng = 0.0,
    this.notes = '',
    this.farmId = '',
    this.farmName = '',
    this.cropName = '',
    this.cropId = '',
    this.sowingDate = '',
    this.address = '',
    this.nitrogen = 0.0,
    this.phosphorus = 0.0,
    this.potassium = 0.0,
    this.ph = 0.0,
    this.moisture = 0.0,
    this.temperature = 0.0,
    this.ec = 0.0,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  final String id;
  final DateTime timestamp;
  double lat;
  double lng;
  String notes;

  /// Id of the farm this sample belongs to (see `FarmCatalog`).
  final String farmId;

  // Sample metadata (captured via the ADD SAMPLE form)
  final String farmName;
  final String cropName;
  final String cropId;
  final String sowingDate; // YYYY-MM-DD
  final String address;

  // Sensor fields
  final double nitrogen;
  final double phosphorus;
  final double potassium;
  final double ph;
  final double moisture;
  final double temperature;
  final double ec;

  /// Parse rows from the `soil_samples` table (and legacy live/captured rows).
  factory SoilSample.fromMap(Map<String, dynamic> map) {
    return SoilSample(
      id: map['id']?.toString(),
      timestamp: _parseDateTime(
        map['captured_at'] ?? map['timestamp'] ?? map['recorded_at'] ?? map['created_at'],
      ),
      lat: _parseDouble(map['lat'] ?? map['latitude']),
      lng: _parseDouble(map['lng'] ?? map['longitude']),
      notes: (map['notes'] ?? '').toString(),
      farmId: (map['farm_id'] ?? map['farmId'] ?? '').toString(),
      farmName: (map['farm_name'] ?? map['farmName'] ?? '').toString(),
      cropName: (map['crop_name'] ?? map['cropName'] ?? '').toString(),
      cropId: (map['crop_id'] ?? map['cropId'] ?? '').toString(),
      sowingDate: (map['sowing_date'] ?? map['sowingDate'] ?? '').toString(),
      address: (map['address'] ?? map['farm_address'] ?? '').toString(),
      nitrogen: _parseDouble(map['n'] ?? map['nitrogen']),
      phosphorus: _parseDouble(map['p'] ?? map['phosphorus']),
      potassium: _parseDouble(map['k'] ?? map['potassium']),
      ph: _parseDouble(map['ph']),
      moisture: _parseDouble(map['moist'] ?? map['moisture']),
      temperature: _parseDouble(map['temp'] ?? map['temperature']),
      ec: _parseDouble(map['ec']),
    );
  }

  /// Serialize a captured sample for the Supabase `soil_samples` table.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'captured_at': timestamp.toUtc().toIso8601String(),
      'lat': lat,
      'lng': lng,
      'notes': notes,
      'farm_id': farmId,
      'farm_name': farmName,
      'crop_name': cropName,
      'crop_id': cropId,
      // Sent as null rather than '' so a `date` column accepts the row even if
      // a sample is ever built without a sowing date.
      'sowing_date': sowingDate.isEmpty ? null : sowingDate,
      'address': address,
      'n': nitrogen,
      'p': phosphorus,
      'k': potassium,
      'ph': ph,
      'moist': moisture,
      'temp': temperature,
      'ec': ec,
    };
  }

  /// Short human label used by the DSS sample picker.
  String get label {
    final crop = cropName.isEmpty ? 'Sample' : cropName;
    final plot = farmName.isEmpty ? '' : ' · $farmName';
    return '$crop$plot';
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
    }
    return DateTime.now();
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
