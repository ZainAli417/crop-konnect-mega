import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/crop_timeline.dart';

/// Loads the day-range crop stage timelines from the moisture-ranges asset.
/// Only crops that carry `start_day` stages (the field-sheet crops) are exposed
/// here; legacy moisture-only entries are ignored.
class CropTimelineRepository {
  CropTimelineRepository({
    this.assetPath = 'assets/crop_moisture_ranges.json',
  });

  final String assetPath;
  List<CropTimeline>? _cache;

  Future<List<CropTimeline>> load() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Crop timeline dataset must be a JSON object.');
    }

    final timelines = <CropTimeline>[];
    decoded.forEach((key, value) {
      if (CropTimeline.isTimeline(value)) {
        timelines.add(CropTimeline.fromJson(key, value as Map<String, dynamic>));
      }
    });

    timelines.sort((a, b) => a.crop.toLowerCase().compareTo(b.crop.toLowerCase()));
    if (timelines.isEmpty) {
      throw const FormatException('No crop stage timelines were found.');
    }
    _cache = timelines;
    return timelines;
  }

  CropTimeline resolve(List<CropTimeline> timelines, String? id) {
    if (timelines.isEmpty) {
      throw StateError('No crop timelines loaded.');
    }
    final norm = _normalize(id ?? '');
    if (norm.isNotEmpty) {
      for (final t in timelines) {
        if (_normalize(t.id) == norm || _normalize(t.crop) == norm) return t;
      }
      for (final t in timelines) {
        if (_normalize(t.crop).contains(norm) || norm.contains(_normalize(t.id))) {
          return t;
        }
      }
    }
    return timelines.firstWhere(
      (t) => t.id == 'wheat',
      orElse: () => timelines.first,
    );
  }

  String _normalize(String v) => v
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}
