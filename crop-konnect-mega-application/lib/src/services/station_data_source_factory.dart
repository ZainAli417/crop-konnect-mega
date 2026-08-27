import '../config/app_config.dart';
import 'backend_client.dart';
import 'mock_station_data_source.dart';
import 'station_data_source.dart';
import 'supabase_station_data_source.dart';

class StationDataSourceFactory {
  static StationDataSource create({
    required AppDataMode mode,
    required String baseUrl,
    required String deviceId,
    required String stationName,
  }) {
    switch (mode) {
      case AppDataMode.supabase:
        return SupabaseStationDataSource(
          supabaseUrl: AppConfig.supabaseUrl,
          anonKey: AppConfig.supabaseAnonKey,
          deviceId: deviceId,
          stationName: stationName,
        );
      case AppDataMode.mock:
        return MockStationDataSource(
          deviceId: deviceId,
          stationName: stationName,
        );
      case AppDataMode.live:
        return BackendClient(
          baseUrl: baseUrl,
          deviceId: deviceId,
        );
    }
  }
}
