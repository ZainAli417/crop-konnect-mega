import 'dart:async';

import '../config/app_config.dart';
import '../models/irrigation.dart';
import '../models/monitoring_status.dart';
import '../models/sensor_reading.dart';
import '../models/station_settings.dart';
import '../models/station_summary.dart';
import '../models/station_trends.dart';
import '../models/gps_reading.dart';

abstract class StationDataSource {
  AppDataMode get mode;

  String get modeLabel;

  Future<SensorReading> fetchLatestReading();

  Future<StationSummary> fetchSummary({int hours = 24});

  Future<MonitoringStatus> fetchMonitoringStatus();

  Future<StationTrends> fetchTrends({int hours = 24});

  Future<GpsReading?> fetchLatestGpsReading();

  Future<StationSettings> fetchSettings();

  Future<StationSettings> patchSettings(StationSettingsPatch patch);

  Future<List<IrrigationCropOption>> fetchIrrigationPresets();

  Future<IrrigationProfile> fetchIrrigationProfile();

  Future<IrrigationProfile> patchIrrigationProfile(
      IrrigationProfilePatch patch);

  Future<IrrigationAdvisory?> fetchLatestIrrigationAdvisory();

  /// Connect to a realtime stream of new sensor readings.
  /// Returns null if the data source does not support realtime.
  Future<Stream<SensorReading>?> connectRealtime() async => null;

  /// Dispose any active realtime subscriptions.
  void disposeRealtime() {}
}
