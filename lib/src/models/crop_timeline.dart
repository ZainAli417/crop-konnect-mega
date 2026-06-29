// ════════════════════════════════════════════════════════════════════════════
//  Crop Stage Timeline
//  Each crop carries an ordered list of growth stages with day-after-sowing
//  ranges (sourced from the 32-crop field sheet) plus the agronomic targets the
//  DSS compares live sensors against. The current stage is computed purely from
//  the sowing date — no manual stage picking.
// ════════════════════════════════════════════════════════════════════════════

class TimelineStage {
  const TimelineStage({
    required this.name,
    required this.startDay,
    required this.endDay,
    required this.moistureLower,
    required this.moistureUpper,
    required this.sensitivity,
    required this.nDemand,
    required this.pDemand,
    required this.kDemand,
    required this.tempOptMin,
    required this.tempOptMax,
    required this.icon,
    required this.focus,
  });

  final String name;
  final int startDay;
  final int endDay;
  final double moistureLower;
  final double moistureUpper;
  final String sensitivity; // high | medium | low
  final String nDemand; // high | medium | low
  final String pDemand;
  final String kDemand;
  final double tempOptMin;
  final double tempOptMax;
  final String icon; // logical key -> mapped to IconData in the UI
  final String focus; // farmer-facing "what matters now" line

  int get span => (endDay - startDay).clamp(1, 100000);

  factory TimelineStage.fromJson(Map<String, dynamic> json) {
    return TimelineStage(
      name: json['stage'] as String? ?? 'Stage',
      startDay: (json['start_day'] as num?)?.round() ?? 0,
      endDay: (json['end_day'] as num?)?.round() ?? 0,
      moistureLower: _d(json['lower_moisture']) ?? 40,
      moistureUpper: _d(json['upper_moisture']) ?? 70,
      sensitivity: json['sensitivity'] as String? ?? 'medium',
      nDemand: json['n_demand'] as String? ?? 'medium',
      pDemand: json['p_demand'] as String? ?? 'medium',
      kDemand: json['k_demand'] as String? ?? 'medium',
      tempOptMin: _d(json['temp_opt_min']) ?? 18,
      tempOptMax: _d(json['temp_opt_max']) ?? 32,
      icon: json['icon'] as String? ?? 'leaf',
      focus: json['focus'] as String? ?? 'Keep conditions steady for this stage.',
    );
  }
}

class CropTimeline {
  const CropTimeline({
    required this.id,
    required this.crop,
    required this.kbName,
    required this.sowWindow,
    required this.totalDays,
    required this.stages,
  });

  final String id; // json key, e.g. "spring_maize"
  final String crop; // display name
  final String kbName; // lookup key into the DSS crop knowledge base
  final String sowWindow; // e.g. "Mid-October"
  final int totalDays;
  final List<TimelineStage> stages;

  /// Index of the stage that contains [das] (days after sowing).
  /// Before the first stage -> 0; after the last -> last index.
  int stageIndexForDay(int das) {
    if (stages.isEmpty) return 0;
    for (var i = 0; i < stages.length; i++) {
      if (das <= stages[i].endDay) return i;
    }
    return stages.length - 1;
  }

  TimelineStage stageForDay(int das) => stages[stageIndexForDay(das)];

  bool isPastHarvest(int das) =>
      stages.isNotEmpty && das > stages.last.endDay;

  /// 0..1 progress through the whole cycle.
  double cycleProgress(int das) {
    if (totalDays <= 0) return 0;
    return (das / totalDays).clamp(0.0, 1.0);
  }

  factory CropTimeline.fromJson(String id, Map<String, dynamic> json) {
    final rawStages = json['stages'];
    final stages = <TimelineStage>[];
    if (rawStages is List) {
      for (final item in rawStages) {
        if (item is Map<String, dynamic>) {
          stages.add(TimelineStage.fromJson(item));
        }
      }
    }
    final total = (json['total_days'] as num?)?.round() ??
        (stages.isNotEmpty ? stages.last.endDay : 120);
    return CropTimeline(
      id: id,
      crop: json['crop'] as String? ?? id,
      kbName: json['kb'] as String? ?? json['crop'] as String? ?? id,
      sowWindow: json['sow_window'] as String? ?? '',
      totalDays: total,
      stages: stages,
    );
  }

  /// Only entries that carry day-range stages are real timelines.
  static bool isTimeline(dynamic value) {
    if (value is! Map<String, dynamic>) return false;
    final stages = value['stages'];
    if (stages is! List || stages.isEmpty) return false;
    final first = stages.first;
    return first is Map<String, dynamic> && first.containsKey('start_day');
  }
}

double? _d(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}
