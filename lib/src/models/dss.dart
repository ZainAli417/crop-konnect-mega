import 'irrigation.dart';
import 'monitoring_status.dart';
import 'sensor_reading.dart';
import 'station_trends.dart';

enum DssUrgency {
  critical,
  high,
  moderate,
  low,
  info,
}

enum DssConfidence {
  high,
  medium,
  low,
}

class DssEvidence {
  const DssEvidence({
    required this.label,
    required this.value,
    required this.status,
  });

  final String label;
  final String value;
  final String status;
}

class DssRecommendation {
  const DssRecommendation({
    required this.id,
    required this.moduleId,
    required this.moduleTitle,
    required this.title,
    required this.decision,
    required this.urgency,
    required this.confidence,
    required this.whyItMatters,
    required this.farmerAction,
    required this.fieldCheck,
    required this.evidence,
  });

  final String id;
  final String moduleId;
  final String moduleTitle;
  final String title;
  final String decision;
  final DssUrgency urgency;
  final DssConfidence confidence;
  final String whyItMatters;
  final String farmerAction;
  final String fieldCheck;
  final List<DssEvidence> evidence;
}

class DssScore {
  const DssScore({
    required this.value,
    required this.label,
    required this.summary,
  });

  final int value;
  final String label;
  final String summary;
}

class DssModuleResult {
  const DssModuleResult({
    required this.id,
    required this.title,
    required this.score,
    required this.status,
    required this.summary,
    required this.recommendations,
  });

  final String id;
  final String title;
  final int score;
  final String status;
  final String summary;
  final List<DssRecommendation> recommendations;
}

class DssAnalysis {
  const DssAnalysis({
    required this.generatedAt,
    required this.crop,
    required this.stage,
    required this.fieldScore,
    required this.priorityRecommendations,
    required this.modules,
    required this.dataConfidence,
    required this.sourceSummary,
  });

  final DateTime generatedAt;
  final DssCropProfile crop;
  final DssCropStage stage;
  final DssScore fieldScore;
  final List<DssRecommendation> priorityRecommendations;
  final List<DssModuleResult> modules;
  final DssConfidence dataConfidence;
  final String sourceSummary;

  List<DssRecommendation> get allRecommendations {
    return modules
        .expand((module) => module.recommendations)
        .toList(growable: false);
  }
}

class DssCropProfile {
  const DssCropProfile({
    required this.id,
    required this.name,
    required this.group,
    required this.aliases,
    required this.pakistanRegions,
    required this.seasons,
    required this.phMin,
    required this.phMax,
    required this.ecThresholdDsM,
    required this.salinityTolerance,
    required this.tempOptimalMinC,
    required this.tempOptimalMaxC,
    required this.tempHotC,
    required this.tempColdC,
    required this.nDemand,
    required this.pDemand,
    required this.kDemand,
    required this.diseaseTempMinC,
    required this.diseaseTempMaxC,
    required this.pestRisk,
    required this.stages,
    required this.notes,
    required this.confidence,
    required this.sources,
  });

  final String id;
  final String name;
  final String group;
  final List<String> aliases;
  final List<String> pakistanRegions;
  final List<String> seasons;
  final double phMin;
  final double phMax;
  final double ecThresholdDsM;
  final String salinityTolerance;
  final double tempOptimalMinC;
  final double tempOptimalMaxC;
  final double tempHotC;
  final double tempColdC;
  final String nDemand;
  final String pDemand;
  final String kDemand;
  final double diseaseTempMinC;
  final double diseaseTempMaxC;
  final String pestRisk;
  final List<DssCropStage> stages;
  final String notes;
  final String confidence;
  final List<String> sources;

  factory DssCropProfile.fromJson(Map<String, dynamic> json) {
    final ph = json['ph'] as Map<String, dynamic>? ?? const {};
    final ec = json['ec'] as Map<String, dynamic>? ?? const {};
    final temp =
        json['temperature_c'] as Map<String, dynamic>? ?? const {};
    final nutrients =
        json['nutrient_demand'] as Map<String, dynamic>? ?? const {};
    final risks = json['risk_triggers'] as Map<String, dynamic>? ?? const {};
    final pakistan = json['pakistan'] as Map<String, dynamic>? ?? const {};

    return DssCropProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Crop',
      group: json['group'] as String? ?? 'general',
      aliases: _stringList(json['aliases']),
      pakistanRegions: _stringList(pakistan['regions']),
      seasons: _stringList(pakistan['seasons']),
      phMin: _asDouble(ph['min']) ?? 6.0,
      phMax: _asDouble(ph['max']) ?? 7.8,
      ecThresholdDsM: _asDouble(ec['threshold_dsm']) ?? 2.0,
      salinityTolerance: ec['tolerance'] as String? ?? 'moderate',
      tempOptimalMinC: _asDouble(temp['optimal_min']) ?? 18,
      tempOptimalMaxC: _asDouble(temp['optimal_max']) ?? 32,
      tempHotC: _asDouble(temp['hot']) ?? 36,
      tempColdC: _asDouble(temp['cold']) ?? 10,
      nDemand: nutrients['n'] as String? ?? 'medium',
      pDemand: nutrients['p'] as String? ?? 'medium',
      kDemand: nutrients['k'] as String? ?? 'medium',
      diseaseTempMinC: _asDouble(risks['disease_temp_min']) ?? 18,
      diseaseTempMaxC: _asDouble(risks['disease_temp_max']) ?? 30,
      pestRisk: risks['pest_risk'] as String? ?? 'medium',
      stages: (json['stages'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(DssCropStage.fromJson)
          .toList(growable: false),
      notes: json['notes'] as String? ?? '',
      confidence: json['confidence'] as String? ?? 'medium',
      sources: _stringList(json['sources']),
    );
  }

  DssCropStage stageByName(String? stageName) {
    if (stages.isEmpty) {
      return const DssCropStage(
        name: 'General',
        moistureLower: 40,
        moistureUpper: 70,
        sensitivity: 'medium',
        nDemand: 'medium',
        pDemand: 'medium',
        kDemand: 'medium',
        actionNote: 'Watch the crop and compare readings with field condition.',
      );
    }
    final normalized = _normalize(stageName ?? '');
    for (final stage in stages) {
      if (_normalize(stage.name) == normalized) {
        return stage;
      }
    }
    for (final stage in stages) {
      if (normalized.isNotEmpty &&
          (_normalize(stage.name).contains(normalized) ||
              normalized.contains(_normalize(stage.name)))) {
        return stage;
      }
    }
    return stages.first;
  }

  static String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }
}

class DssCropStage {
  const DssCropStage({
    required this.name,
    required this.moistureLower,
    required this.moistureUpper,
    required this.sensitivity,
    required this.nDemand,
    required this.pDemand,
    required this.kDemand,
    required this.actionNote,
  });

  final String name;
  final double moistureLower;
  final double moistureUpper;
  final String sensitivity;
  final String nDemand;
  final String pDemand;
  final String kDemand;
  final String actionNote;

  factory DssCropStage.fromJson(Map<String, dynamic> json) {
    return DssCropStage(
      name: json['name'] as String? ?? 'General',
      moistureLower: _asDouble(json['moisture_lower']) ?? 40,
      moistureUpper: _asDouble(json['moisture_upper']) ?? 70,
      sensitivity: json['sensitivity'] as String? ?? 'medium',
      nDemand: json['n_demand'] as String? ?? 'medium',
      pDemand: json['p_demand'] as String? ?? 'medium',
      kDemand: json['k_demand'] as String? ?? 'medium',
      actionNote: json['action_note'] as String? ??
          'Watch this stage closely and confirm with field observation.',
    );
  }
}

class DssInput {
  const DssInput({
    required this.crop,
    required this.stage,
    required this.reading,
    required this.trends,
    required this.monitoring,
    required this.irrigationProfile,
  });

  final DssCropProfile crop;
  final DssCropStage stage;
  final SensorReading? reading;
  final StationTrends? trends;
  final MonitoringStatus? monitoring;
  final IrrigationProfile? irrigationProfile;
}

List<String> _stringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.whereType<String>().toList(growable: false);
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
