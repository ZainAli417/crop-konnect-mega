class IrrigationCropOption {
  const IrrigationCropOption({
    required this.crop,
    required this.stages,
  });

  final String crop;
  final List<String> stages;

  factory IrrigationCropOption.fromJson(Map<String, dynamic> json) {
    final rawStages = json['stages'];
    return IrrigationCropOption(
      crop: json['crop'] as String? ?? '',
      stages: rawStages is List
          ? rawStages.whereType<String>().toList()
          : const <String>[],
    );
  }
}

class IrrigationProfile {
  const IrrigationProfile({
    required this.id,
    required this.deviceId,
    required this.stationName,
    required this.crop,
    required this.cropStage,
    required this.smartIrrigationEnabled,
    required this.moistureLowerTarget,
    required this.moistureUpperTarget,
    required this.effectiveRainMm,
    required this.rainWindowHours,
    required this.highTempC,
    required this.highSolarWm2,
    required this.highWindMs,
    required this.staleAfterMinutes,
    required this.updatedAt,
  });

  final int id;
  final String deviceId;
  final String? stationName;
  final String crop;
  final String cropStage;
  final bool smartIrrigationEnabled;
  final double moistureLowerTarget;
  final double moistureUpperTarget;
  final double effectiveRainMm;
  final int rainWindowHours;
  final double highTempC;
  final double highSolarWm2;
  final double highWindMs;
  final int staleAfterMinutes;
  final DateTime? updatedAt;

  factory IrrigationProfile.fromJson(Map<String, dynamic> json) {
    return IrrigationProfile(
      id: (json['id'] as num?)?.toInt() ?? 0,
      deviceId: json['device_id'] as String? ?? '',
      stationName: json['station_name'] as String?,
      crop: json['crop'] as String? ?? '',
      cropStage: json['crop_stage'] as String? ?? '',
      smartIrrigationEnabled: json['smart_irrigation_enabled'] == true,
      moistureLowerTarget: _asDouble(json['moisture_lower_target']) ?? 0,
      moistureUpperTarget: _asDouble(json['moisture_upper_target']) ?? 0,
      effectiveRainMm: _asDouble(json['effective_rain_mm']) ?? 0,
      rainWindowHours: (json['rain_window_hours'] as num?)?.toInt() ?? 0,
      highTempC: _asDouble(json['high_temp_c']) ?? 0,
      highSolarWm2: _asDouble(json['high_solar_wm2']) ?? 0,
      highWindMs: _asDouble(json['high_wind_ms']) ?? 0,
      staleAfterMinutes: (json['stale_after_minutes'] as num?)?.toInt() ?? 0,
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }
}

class IrrigationProfilePatch {
  const IrrigationProfilePatch({
    this.crop,
    this.cropStage,
    this.smartIrrigationEnabled,
  });

  final String? crop;
  final String? cropStage;
  final bool? smartIrrigationEnabled;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (crop != null) 'crop': crop,
      if (cropStage != null) 'crop_stage': cropStage,
      if (smartIrrigationEnabled != null)
        'smart_irrigation_enabled': smartIrrigationEnabled,
    };
  }
}

class IrrigationAdvisory {
  const IrrigationAdvisory({
    required this.id,
    required this.deviceId,
    required this.stationName,
    required this.readingId,
    required this.generatedAt,
    required this.decision,
    required this.urgency,
    required this.dataStatus,
    required this.title,
    required this.message,
    required this.reason,
    required this.conditionSummary,
    required this.factors,
    required this.profileSnapshot,
  });

  final int id;
  final String deviceId;
  final String? stationName;
  final int? readingId;
  final DateTime generatedAt;
  final String decision;
  final String urgency;
  final String dataStatus;
  final String title;
  final String message;
  final String reason;
  final String conditionSummary;
  final Map<String, dynamic> factors;
  final Map<String, dynamic> profileSnapshot;

  factory IrrigationAdvisory.fromJson(Map<String, dynamic> json) {
    return IrrigationAdvisory(
      id: (json['id'] as num?)?.toInt() ?? 0,
      deviceId: json['device_id'] as String? ?? '',
      stationName: json['station_name'] as String?,
      readingId: (json['reading_id'] as num?)?.toInt(),
      generatedAt: _parseDateTime(json['generated_at']) ?? DateTime.now(),
      decision: json['decision'] as String? ?? 'unknown',
      urgency: json['urgency'] as String? ?? 'none',
      dataStatus: json['data_status'] as String? ?? 'unknown',
      title: json['title'] as String? ?? 'Irrigation advisory',
      message: json['message'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      conditionSummary: json['condition_summary'] as String? ?? '',
      factors: json['factors'] is Map<String, dynamic>
          ? json['factors'] as Map<String, dynamic>
          : const <String, dynamic>{},
      profileSnapshot: json['profile_snapshot'] is Map<String, dynamic>
          ? json['profile_snapshot'] as Map<String, dynamic>
          : const <String, dynamic>{},
    );
  }

  double? get moistureValue {
    final soil = factors['soil_moisture'];
    if (soil is Map<String, dynamic>) {
      return _asDouble(soil['value']);
    }
    return null;
  }

  double? get lowerTarget {
    final soil = factors['soil_moisture'];
    if (soil is Map<String, dynamic>) {
      return _asDouble(soil['lower_target']);
    }
    return null;
  }

  double? get upperTarget {
    final soil = factors['soil_moisture'];
    if (soil is Map<String, dynamic>) {
      return _asDouble(soil['upper_target']);
    }
    return null;
  }
}

double? _asDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value.toString());
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString())?.toLocal();
}
