import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../services/farm_repository.dart';

/// A logger / weather station installed on a farm.
///
/// [deviceId] is the station device id the dashboard polls (see
/// `AppConfig.deviceId`), so selecting a logger resolves straight to the
/// readings the rest of the app is showing.
class FarmLogger {
  const FarmLogger({
    required this.id,
    required this.name,
    required this.deviceId,
    this.kind = 'Weather + Soil Logger',
  });

  final String id;
  final String name;
  final String deviceId;
  final String kind;
}

/// A farm the app can show a dashboard for.
class Farm {
  const Farm({
    required this.id,
    required this.name,
    required this.location,
    required this.areaAcres,
    required this.primaryCrop,
    required this.loggers,
  });

  final String id;
  final String name;
  final String location;
  final double areaAcres;
  final String primaryCrop;
  final List<FarmLogger> loggers;

  /// The farm's main logger, or null when none is installed.
  FarmLogger? get primaryLogger => loggers.isEmpty ? null : loggers.first;

  /// Parse a `farms` row, or return null when it has no usable id.
  ///
  /// Every field is defensive: a missing name falls back to the id, missing
  /// text becomes '', and a malformed/absent embedded station simply yields a
  /// farm with no loggers. Nothing here throws.
  static Farm? tryFromMap(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString().trim();
    if (id.isEmpty) return null;

    final name = (map['name'] ?? '').toString().trim();

    return Farm(
      id: id,
      name: name.isEmpty ? id : name,
      location: (map['location'] ?? '').toString(),
      areaAcres: _asDouble(map['area_acres']),
      primaryCrop: (map['primary_crop'] ?? '').toString(),
      loggers: _loggersFromRow(map),
    );
  }

  /// Builds the logger list from the embedded `stations(...)` selection.
  /// PostgREST returns a map for a to-one relation, but older versions and
  /// views can return a single-element list — both are handled.
  static List<FarmLogger> _loggersFromRow(Map<String, dynamic> map) {
    final raw = map['stations'] ?? map['station'];

    Map<String, dynamic>? station;
    if (raw is Map) {
      station = Map<String, dynamic>.from(raw);
    } else if (raw is List && raw.isNotEmpty && raw.first is Map) {
      station = Map<String, dynamic>.from(raw.first as Map);
    }

    // No joined station row — fall back to the bare station_id if present so
    // the farm still reports "one logger installed".
    if (station == null) {
      final stationId = map['station_id'];
      if (stationId == null) return const <FarmLogger>[];
      return <FarmLogger>[
        FarmLogger(
          id: 'station-$stationId',
          name: AppConfig.stationName,
          deviceId: AppConfig.deviceId,
        ),
      ];
    }

    final deviceId = (station['device_id'] ?? '').toString().trim();
    if (deviceId.isEmpty) return const <FarmLogger>[];

    final stationName = (station['name'] ?? '').toString().trim();
    final stationId = (station['id'] ?? map['station_id'] ?? deviceId).toString();

    return <FarmLogger>[
      FarmLogger(
        id: 'station-$stationId',
        name: stationName.isEmpty ? deviceId : stationName,
        deviceId: deviceId,
      ),
    ];
  }

  static double _asDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }
}

/// The farms the app knows about.
///
/// Backed by the Supabase `farms` table via [load]. Until that completes — and
/// if it fails, returns nothing, or Supabase is not configured — the built-in
/// [_fallback] is served instead. [farms] is therefore **never empty** and
/// [primary] is **never null**, so callers never have to null-check.
class FarmCatalog {
  FarmCatalog._();

  /// Used until (or unless) the table loads. Keep the id in sync with the
  /// seeded row in `supabase/soil_samples.sql`.
  static const List<Farm> _fallback = <Farm>[
    Farm(
      id: 'farm-001',
      name: 'Gardezi Farm',
      location: 'Multan, Punjab',
      areaAcres: 42.5,
      primaryCrop: 'Wheat',
      loggers: <FarmLogger>[
        FarmLogger(
          id: 'logger-001',
          name: AppConfig.stationName,
          deviceId: AppConfig.deviceId,
        ),
      ],
    ),
  ];

  static List<Farm> _loaded = const <Farm>[];
  static bool _hasLoaded = false;
  static String? _lastError;
  static Future<List<Farm>>? _inFlight;

  /// Bumped after every load attempt.
  ///
  /// The navigation shell caches its tab widgets, so a `setState` up there does
  /// not rebuild them. Screens that display farms listen to this instead — see
  /// `HomeTab` — which is what makes a newly loaded list actually appear.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Always at least one farm.
  static List<Farm> get farms => _loaded.isNotEmpty ? _loaded : _fallback;

  /// The default farm. Never null.
  static Farm get primary => farms.first;

  /// True once a load attempt has finished (successfully or not).
  static bool get hasLoaded => _hasLoaded;

  /// Set when the last load failed; null when it succeeded.
  static String? get lastError => _lastError;

  /// True when the list being served is the built-in fallback.
  static bool get isFallback => _loaded.isEmpty;

  static Farm? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final farm in farms) {
      if (farm.id == id) return farm;
    }
    return null;
  }

  /// Resolve an id to a farm, falling back to [primary]. Never null — use this
  /// wherever a stale or unknown id could otherwise produce a null.
  static Farm resolve(String? id) => byId(id) ?? primary;

  /// Load the farm list from Supabase.
  ///
  /// Never throws and never leaves the catalogue empty: on any failure the
  /// fallback stays in place and [lastError] is set. Concurrent calls share one
  /// request; pass `force: true` to refetch after that.
  static Future<List<Farm>> load({
    FarmRepository repository = const FarmRepository(),
    bool force = false,
  }) {
    final inFlight = _inFlight;
    if (inFlight != null && !force) return inFlight;

    final request = _load(repository);
    _inFlight = request;
    return request;
  }

  static Future<List<Farm>> _load(FarmRepository repository) async {
    try {
      final rows = await repository.fetchFarms();
      if (rows.isNotEmpty) {
        _loaded = rows;
        _lastError = null;
      } else {
        // Table reachable but empty — keep the fallback rather than showing
        // an empty home screen.
        _lastError = null;
      }
    } catch (error) {
      _lastError = error.toString();
      debugPrint('Farm load failed, using built-in farm list: $error');
    } finally {
      _hasLoaded = true;
      _inFlight = null;
      revision.value++;
    }
    return farms;
  }

  /// Test/debug hook: drop the cache so the next [load] refetches.
  @visibleForTesting
  static void reset() {
    _loaded = const <Farm>[];
    _hasLoaded = false;
    _lastError = null;
    _inFlight = null;
    revision.value++;
  }
}
