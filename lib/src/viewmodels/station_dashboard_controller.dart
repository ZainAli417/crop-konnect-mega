import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/irrigation.dart';
import '../models/monitoring_status.dart';
import '../models/sensor_reading.dart';
import '../models/station_settings.dart';
import '../models/station_summary.dart';
import '../models/station_trends.dart';
import '../models/dss.dart';
import '../services/dss_crop_repository.dart';
import '../services/dss_engine.dart';
import '../services/station_data_source.dart';
import '../services/station_live_stream.dart';
import '../models/gps_reading.dart';

class StationDashboardController extends ChangeNotifier {
  StationDashboardController({
    required StationDataSource client,
    StationLiveStream? liveStream,
  })  : _client = client,
        _liveStream = liveStream;

  final StationDataSource _client;
  final StationLiveStream? _liveStream;

  SensorReading? latestReading;
  StationSummary? summary;
  MonitoringStatus? monitoringStatus;
  StationSettings? stationSettings;
  StationTrends? trends;
  List<IrrigationCropOption> irrigationPresets = const <IrrigationCropOption>[];
  IrrigationProfile? irrigationProfile;
  IrrigationAdvisory? latestIrrigationAdvisory;
  List<DssCropProfile> dssCropProfiles = const <DssCropProfile>[];
  DssCropProfile? activeDssCrop;
  DssCropStage? activeDssStage;
  DssAnalysis? dssAnalysis;
  GpsReading? gpsReading;
  String? errorMessage;
  String? dssErrorMessage;
  bool isLoading = true;
  bool hasConnection = false;
  bool isApplyingSettings = false;
  bool isApplyingIrrigation = false;

  Timer? _monitoringTimer;
  Timer? _irrigationTimer;
  Timer? _trendsTimer;
  Timer? _gpsTimer;
  StreamSubscription<SensorReading>? _liveSubscription;
  StreamSubscription<SensorReading>? _realtimeSubscription;
  bool _refreshingFromStream = false;
  final DssCropKnowledgeRepository _dssCropRepository =
      DssCropKnowledgeRepository();
  final DssEngine _dssEngine = const DssEngine();

  AppDataMode get mode => _client.mode;

  String get modeLabel => _client.modeLabel;

  Future<void> start() async {
    await refreshAll();
    if (_liveStream != null) {
      _liveSubscription = _liveStream.connect().listen(_handleLiveReading);
    }
    // Connect Supabase realtime listener if supported
    try {
      final realtimeStream = await _client.connectRealtime();
      if (realtimeStream != null) {
        _realtimeSubscription = realtimeStream.listen(_handleLiveReading);
      }
    } catch (_) {
      // Realtime is optional; polling continues as fallback.
    }
    _monitoringTimer = Timer.periodic(
        AppConfig.monitoringRefreshInterval, (_) => refreshMonitoringStatus());
    _irrigationTimer = Timer.periodic(
      AppConfig.summaryRefreshInterval,
      (_) => refreshIrrigation(),
    );
    _trendsTimer =
        Timer.periodic(AppConfig.trendsRefreshInterval, (_) => refreshTrends());
    _gpsTimer = Timer.periodic(
        AppConfig.monitoringRefreshInterval, (_) => refreshGpsReading());
  }

  Future<void> refreshAll() async {
    isLoading = true;
    notifyListeners();

    await Future.wait<void>([
      refreshSummary(notify: false),
      refreshMonitoringStatus(notify: false),
      refreshTrends(notify: false),
      refreshSettings(notify: false),
      refreshIrrigation(notify: false),
      refreshGpsReading(notify: false),
    ]);
    await refreshDss(notify: false);

    isLoading = false;
    notifyListeners();
  }

  Future<void> _handleLiveReading(SensorReading reading) async {
    latestReading = reading;
    hasConnection = true;
    errorMessage = null;
    notifyListeners();

    if (_refreshingFromStream) {
      return;
    }

    _refreshingFromStream = true;
    try {
      await refreshMonitoringStatus(notify: false);
      if (irrigationProfile?.smartIrrigationEnabled ?? false) {
        await refreshIrrigation(notify: false);
      }
      await refreshGpsReading(notify: false);
      await refreshDss(notify: false);
      notifyListeners();
    } finally {
      _refreshingFromStream = false;
    }
  }

  Future<void> refreshLatest({bool notify = true}) async {
    try {
      latestReading = await _client.fetchLatestReading();
      await refreshDss(notify: false);
      hasConnection = true;
      errorMessage = null;
    } catch (error) {
      hasConnection = false;
      errorMessage = error.toString();
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> refreshSummary({bool notify = true}) async {
    try {
      summary = await _client.fetchSummary();
      hasConnection = true;
      errorMessage = null;
    } catch (error) {
      hasConnection = false;
      errorMessage = error.toString();
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> refreshMonitoringStatus({bool notify = true}) async {
    try {
      final status = await _client.fetchMonitoringStatus();
      monitoringStatus = status;
      latestReading = status.latest ?? latestReading;
      await refreshDss(notify: false);
      hasConnection = true;
      errorMessage = null;
    } catch (error) {
      hasConnection = false;
      errorMessage = error.toString();
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> refreshTrends({bool notify = true}) async {
    try {
      trends = await _client.fetchTrends();
      await refreshDss(notify: false);
    } catch (error) {
      if (trends == null && !hasConnection) {
        errorMessage = error.toString();
      }
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> refreshSettings({bool notify = true}) async {
    try {
      stationSettings = await _client.fetchSettings();
      hasConnection = true;
      errorMessage = null;
    } catch (error) {
      if (stationSettings == null && !hasConnection) {
        errorMessage = error.toString();
      }
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> refreshIrrigation({bool notify = true}) async {
    try {
      if (irrigationPresets.isEmpty) {
        irrigationPresets = await _client.fetchIrrigationPresets();
      }
      irrigationProfile = await _client.fetchIrrigationProfile();
      latestIrrigationAdvisory = irrigationProfile!.smartIrrigationEnabled
          ? await _client.fetchLatestIrrigationAdvisory()
          : null;
      await refreshDss(notify: false);
      hasConnection = true;
      errorMessage = null;
    } catch (error) {
      if (irrigationProfile == null && !hasConnection) {
        errorMessage = error.toString();
      }
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> refreshDss({bool notify = true}) async {
    try {
      if (dssCropProfiles.isEmpty) {
        dssCropProfiles = await _dssCropRepository.loadProfiles();
      }
      final crop = _dssCropRepository.resolveCrop(
        dssCropProfiles,
        irrigationProfile?.crop,
      );
      final stage = crop.stageByName(irrigationProfile?.cropStage);
      activeDssCrop = crop;
      activeDssStage = stage;
      dssAnalysis = _dssEngine.analyze(
        DssInput(
          crop: crop,
          stage: stage,
          reading: latestReading,
          trends: trends,
          monitoring: monitoringStatus,
          irrigationProfile: irrigationProfile,
        ),
      );
      dssErrorMessage = null;
    } catch (error) {
      dssErrorMessage = error.toString();
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> refreshGpsReading({bool notify = true}) async {
    try {
      gpsReading = await _client.fetchLatestGpsReading();
      hasConnection = true;
      errorMessage = null;
    } catch (error) {
      // GPS failure is optional; don't break connection status
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> updateSmartIrrigation({
    required bool enabled,
    String? crop,
    String? cropStage,
  }) async {
    isApplyingIrrigation = true;
    notifyListeners();

    try {
      irrigationProfile = await _client.patchIrrigationProfile(
        IrrigationProfilePatch(
          crop: enabled ? crop : null,
          cropStage: enabled ? cropStage : null,
          smartIrrigationEnabled: enabled,
        ),
      );
      latestIrrigationAdvisory = irrigationProfile!.smartIrrigationEnabled
          ? await _client.fetchLatestIrrigationAdvisory()
          : null;
      await refreshDss(notify: false);
      hasConnection = true;
      errorMessage = null;
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isApplyingIrrigation = false;
      notifyListeners();
    }
  }

  Future<void> patchSettings(StationSettingsPatch patch) async {
    isApplyingSettings = true;
    notifyListeners();

    try {
      stationSettings = await _client.patchSettings(patch);
      hasConnection = true;
      errorMessage = null;
      await refreshMonitoringStatus(notify: false);
      await refreshDss(notify: false);
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isApplyingSettings = false;
      notifyListeners();
    }
  }

  Future<void> setSensorEnabled(String sensorKey, bool enabled) async {
    await patchSettings(
      StationSettingsPatch(
        sensorEnabled: <String, bool>{sensorKey: enabled},
      ),
    );
  }

  Future<void> setAllSensorsEnabled(bool enabled) async {
    await patchSettings(
      StationSettingsPatch(
        sensorEnabled: <String, bool>{
          'wind_speed': enabled,
          'wind_direction': enabled,
          'soil': enabled,
          'rain': enabled,
          'uv': enabled,
        },
      ),
    );
  }

  Future<void> updatePolling({
    int? pollIntervalSeconds,
    int? interReadDelayMs,
    List<String>? sensorReadOrder,
  }) async {
    await patchSettings(
      StationSettingsPatch(
        pollIntervalSeconds: pollIntervalSeconds,
        interReadDelayMs: interReadDelayMs,
        sensorReadOrder: sensorReadOrder,
      ),
    );
  }

  Future<void> updateSchedule(StationScheduleSettingsPatch schedule) async {
    await patchSettings(
      StationSettingsPatch(schedule: schedule),
    );
  }

  @override
  void dispose() {
    _monitoringTimer?.cancel();
    _irrigationTimer?.cancel();
    _trendsTimer?.cancel();
    _gpsTimer?.cancel();
    _liveSubscription?.cancel();
    _realtimeSubscription?.cancel();
    _liveStream?.dispose();
    _client.disposeRealtime();
    super.dispose();
  }
}
