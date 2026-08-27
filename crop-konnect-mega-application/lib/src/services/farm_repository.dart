import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/farm.dart';

/// Reads the farm list from the Supabase `farms` table.
///
/// The embedded `stations(...)` selection resolves each farm's installed logger
/// through the `farms.station_id` foreign key, so a farm arrives with the
/// device id the dashboard needs to poll.
///
/// See `supabase/soil_samples.sql` for the table definition.
class FarmRepository {
  const FarmRepository();

  static const String table = 'farms';

  static const String _select =
      'id,name,location,area_acres,primary_crop,station_id,'
      'stations(id,device_id,name)';

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  /// Fetch every farm, ordered by name.
  ///
  /// Rows that cannot be parsed are skipped rather than failing the whole load,
  /// and a farm with no usable id is dropped — the caller always receives a
  /// list of valid farms (possibly empty).
  Future<List<Farm>> fetchFarms() async {
    final rows = await _client.from(table).select(_select).order('name');

    final farms = <Farm>[];
    for (final row in rows as List<dynamic>) {
      if (row is! Map) continue;
      final farm = Farm.tryFromMap(Map<String, dynamic>.from(row));
      if (farm != null) farms.add(farm);
    }
    return farms;
  }
}
