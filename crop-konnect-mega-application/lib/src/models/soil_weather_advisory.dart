// ════════════════════════════════════════════════════════════════════════════
//  Soil–Weather Advisory (remote DSS)
//  Response model for POST /advisory/api/advisory/soil-weather. The backend
//  takes the crop, sowing date, observation date and the field's latest soil +
//  weather readings and returns a farmer-facing advisory (summary, sections,
//  action points, special-focus items, findings and per-parameter signal
//  comparisons against the crop-stage expected bands).
// ════════════════════════════════════════════════════════════════════════════

class SoilWeatherAdvisory {
  const SoilWeatherAdvisory({
    required this.status,
    required this.advisoryType,
    required this.language,
    required this.summary,
    required this.cropName,
    required this.stage,
    required this.das,
    required this.sections,
    required this.actionPoints,
    required this.specialFocus,
    required this.recommendedActions,
    required this.findings,
    required this.soilSignals,
    required this.weatherSignals,
  });

  final String status;
  final String advisoryType;
  final String language;
  final String summary;

  /// Crop / stage context echoed back by the advisory.
  final String cropName;
  final String stage;
  final int das;

  /// Titled, severity-tagged narrative sections (condition, moisture, nutrients…).
  final List<AdvisorySection> sections;

  /// Plain "do this" action list.
  final List<String> actionPoints;

  /// Readings the farmer should prioritise (out-of-band parameters).
  final List<String> specialFocus;

  /// Consolidated recommended actions.
  final List<String> recommendedActions;

  /// Per-signal findings (each may carry an evidence reading with expected band).
  final List<AdvisoryFinding> findings;

  /// Per-parameter soil sensor comparisons vs the crop-stage band.
  final List<SignalReading> soilSignals;

  /// Per-parameter weather comparisons vs the expected band.
  final List<SignalReading> weatherSignals;

  bool get isCompleted => status.toLowerCase() == 'completed';

  factory SoilWeatherAdvisory.fromJson(Map<String, dynamic> json) {
    final farmer = _asMap(json['farmer_advisory']);
    final cropCtx = _asMap(farmer['crop']);

    // Signals live under farmer_advisory.signals; fall back to top-level.
    final signals = _asMap(farmer['signals']);
    final soilSensor = _asMap(
      signals['soil_sensor'].isNotEmpty
          ? signals['soil_sensor']
          : json['soil_sensor'],
    );
    final soilComparisons = _asMap(soilSensor['comparisons']);
    final weatherStation = _asMap(
      signals['weather_station'].isNotEmpty
          ? signals['weather_station']
          : _asMap(json['weather'])['comparisons'],
    );

    return SoilWeatherAdvisory(
      status: json['status'] as String? ?? 'unknown',
      advisoryType: json['advisory_type'] as String? ?? 'soil',
      language: json['language'] as String? ?? 'en',
      summary: json['summary'] as String? ?? '',
      cropName: (cropCtx['name'] as String?) ?? '',
      stage: (cropCtx['stage'] as String?) ?? '',
      das: _asInt(cropCtx['das']) ?? 0,
      sections: _asList(json['advisory_sections'])
          .map(AdvisorySection.fromJson)
          .toList(growable: false),
      actionPoints: _stringList(json['action_points']),
      specialFocus: _stringList(json['special_focus_on']),
      recommendedActions: _stringList(json['recommended_actions']),
      findings: _asList(json['findings'])
          .map(AdvisoryFinding.fromJson)
          .toList(growable: false),
      soilSignals: soilComparisons.values
          .whereType<Map<String, dynamic>>()
          .map(SignalReading.fromJson)
          .toList(growable: false),
      weatherSignals: weatherStation.values
          .whereType<Map<String, dynamic>>()
          .map(SignalReading.fromJson)
          .toList(growable: false),
    );
  }
}

class AdvisorySection {
  const AdvisorySection({
    required this.key,
    required this.title,
    required this.description,
    required this.severity,
  });

  final String key;
  final String title;
  final String description;
  final String severity;

  factory AdvisorySection.fromJson(Map<String, dynamic> json) {
    return AdvisorySection(
      key: json['key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      severity: json['severity'] as String? ?? 'info',
    );
  }
}

class AdvisoryFinding {
  const AdvisoryFinding({
    required this.severity,
    required this.title,
    required this.message,
    this.evidence,
  });

  final String severity;
  final String title;
  final String message;

  /// Present when the finding is backed by a parameter reading (with a band).
  final SignalReading? evidence;

  factory AdvisoryFinding.fromJson(Map<String, dynamic> json) {
    final ev = _asMap(json['evidence']);
    // Only treat evidence as a signal reading when it carries a parameter.
    final hasReading = ev.containsKey('parameter_code');
    return AdvisoryFinding(
      severity: json['severity'] as String? ?? 'info',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      evidence: hasReading ? SignalReading.fromJson(ev) : null,
    );
  }
}

class SignalReading {
  const SignalReading({
    required this.code,
    required this.label,
    required this.value,
    required this.unit,
    required this.status,
    required this.severity,
    required this.expected,
    required this.message,
    required this.recommendedAction,
  });

  final String code;
  final String label;
  final double? value;
  final String unit;
  final String status;
  final String severity;
  final ExpectedBand? expected;
  final String message;
  final String? recommendedAction;

  factory SignalReading.fromJson(Map<String, dynamic> json) {
    final expected = _asMap(json['expected']);
    return SignalReading(
      code: json['parameter_code'] as String? ?? '',
      label: json['parameter_label'] as String? ?? '',
      value: _asDouble(json['value']),
      unit: json['unit'] as String? ?? '',
      status: json['status'] as String? ?? '',
      severity: json['severity'] as String? ?? 'info',
      expected: expected.isEmpty ? null : ExpectedBand.fromJson(expected),
      message: (json['farmer_message'] as String?) ??
          (json['message'] as String?) ??
          '',
      recommendedAction: json['recommended_action'] as String?,
    );
  }
}

class ExpectedBand {
  const ExpectedBand({
    required this.optimalLow,
    required this.optimalHigh,
    required this.warningLow,
    required this.warningHigh,
    required this.criticalLow,
    required this.criticalHigh,
    required this.confidence,
  });

  final double? optimalLow;
  final double? optimalHigh;
  final double? warningLow;
  final double? warningHigh;
  final double? criticalLow;
  final double? criticalHigh;
  final String confidence;

  factory ExpectedBand.fromJson(Map<String, dynamic> json) {
    return ExpectedBand(
      optimalLow: _asDouble(json['optimal_low']),
      optimalHigh: _asDouble(json['optimal_high']),
      warningLow: _asDouble(json['warning_low']),
      warningHigh: _asDouble(json['warning_high']),
      criticalLow: _asDouble(json['critical_low']),
      criticalHigh: _asDouble(json['critical_high']),
      confidence: json['confidence'] as String? ?? '',
    );
  }
}

// ── parsing helpers ─────────────────────────────────────────────────────────

Map<String, dynamic> _asMap(dynamic value) {
  return value is Map<String, dynamic> ? value : const <String, dynamic>{};
}

List<Map<String, dynamic>> _asList(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value.whereType<Map<String, dynamic>>().toList(growable: false);
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value
      .whereType<String>()
      .where((s) => s.trim().isNotEmpty)
      .toList(growable: false);
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}
