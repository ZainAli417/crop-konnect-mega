import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/dss.dart';

class DssCropKnowledgeRepository {
  DssCropKnowledgeRepository({
    this.assetPath = 'assets/dss_crop_knowledge.json',
  });

  final String assetPath;
  List<DssCropProfile>? _cache;

  Future<List<DssCropProfile>> loadProfiles() async {
    final cached = _cache;
    if (cached != null) {
      return cached;
    }

    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('DSS crop dataset must be a JSON object.');
    }
    final crops = decoded['crops'];
    if (crops is! List) {
      throw const FormatException('DSS crop dataset is missing crops list.');
    }

    final profiles = crops
        .whereType<Map<String, dynamic>>()
        .map(DssCropProfile.fromJson)
        .where(_isValidProfile)
        .toList(growable: false);

    if (profiles.length < 100) {
      throw FormatException(
        'DSS crop dataset must contain at least 100 valid crops. Found ${profiles.length}.',
      );
    }
    _cache = profiles;
    return profiles;
  }

  DssCropProfile resolveCrop(
    List<DssCropProfile> profiles,
    String? cropName,
  ) {
    if (profiles.isEmpty) {
      throw StateError('No DSS crop profiles loaded.');
    }

    final normalized = _normalize(cropName ?? '');
    if (normalized.isNotEmpty) {
      for (final profile in profiles) {
        if (_normalize(profile.name) == normalized ||
            _normalize(profile.id) == normalized ||
            profile.aliases.any((alias) => _normalize(alias) == normalized)) {
          return profile;
        }
      }
      for (final profile in profiles) {
        if (_normalize(profile.name).contains(normalized) ||
            normalized.contains(_normalize(profile.name)) ||
            profile.aliases.any((alias) =>
                _normalize(alias).contains(normalized) ||
                normalized.contains(_normalize(alias)))) {
          return profile;
        }
      }
    }

    return profiles.firstWhere(
      (profile) => _normalize(profile.name) == 'wheat',
      orElse: () => profiles.first,
    );
  }

  bool _isValidProfile(DssCropProfile profile) {
    return profile.id.isNotEmpty &&
        profile.name.isNotEmpty &&
        profile.stages.isNotEmpty &&
        profile.phMin > 0 &&
        profile.phMax > profile.phMin &&
        profile.ecThresholdDsM > 0 &&
        profile.tempHotC > profile.tempColdC;
  }

  String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }
}
