import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/soil_sample.dart';

/// Reads and writes captured soil samples in the Supabase `soil_samples` table.
///
/// The insert/select behaviour is the same as Crop Konnect UNO's
/// `AppState.saveSample` / `fetchSupabaseData` — newest-first ordering on
/// `captured_at`, one row per sample. Samples are additionally scoped by
/// `farm_id` so a farm's history can be pulled on its own.
///
/// The table definition lives in `supabase/soil_samples.sql` — run it once
/// against the project before using this screen.
class SoilSampleRepository {
  const SoilSampleRepository();

  static const String table = 'soil_samples';

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  /// Insert a single captured sample.
  Future<void> saveSample(SoilSample sample) async {
    await _client.from(table).insert([sample.toMap()]);
  }

  /// Fetch samples newest-first. Pass [farmId] to limit the result to one farm.
  Future<List<SoilSample>> fetchSamples({String? farmId, int limit = 200}) async {
    final query = _client.from(table).select();
    final filtered =
        (farmId == null || farmId.isEmpty) ? query : query.eq('farm_id', farmId);

    final rows = await filtered.order('captured_at', ascending: false).limit(limit);

    return (rows as List<dynamic>)
        .map((row) => SoilSample.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }
}
