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
import '../models/crop_timeline.dart';
import '../services/dss_crop_repository.dart';
import '../services/crop_timeline_repository.dart';
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

  // ── Crop stage timeline (sowing-date driven) ──────────────────────────────
  List<CropTimeline> cropTimelines = const <CropTimeline>[];
  CropTimeline? activeTimeline;
  String selectedCropId = 'wheat';
  // Default to a mid-season sowing so the timeline reads as live on first open.
  DateTime sowingDate =
      DateTime.now().subtract(const Duration(days: 75));

  /// Whole days since sowing (never negative).
  int get daysAfterSowing {
    final diff = DateTime.now().difference(sowingDate).inHours / 24.0;
    return diff < 0 ? 0 : diff.floor();
  }

  TimelineStage? get currentTimelineStage {
    final t = activeTimeline;
    if (t == null || t.stages.isEmpty) return null;
    return t.stageForDay(daysAfterSowing);
  }

  int get currentStageIndex {
    final t = activeTimeline;
    if (t == null || t.stages.isEmpty) return 0;
    return t.stageIndexForDay(daysAfterSowing);
  }

  bool get isPastHarvest =>
      activeTimeline?.isPastHarvest(daysAfterSowing) ?? false;
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
  Future<void>? _dssRefreshInFlight;
  String? _lastDssSignature;
  final DssCropKnowledgeRepository _dssCropRepository =
      DssCropKnowledgeRepository();
  final CropTimelineRepository _timelineRepository = CropTimelineRepository();
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
      refreshMonitoringStatus(notify: false, updateDss: false),
      refreshTrends(notify: false, updateDss: false),
      refreshSettings(notify: false),
      refreshIrrigation(notify: false, updateDss: false),
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

    if (_refreshingFromStream) {
      notifyListeners();
      return;
    }

    _refreshingFromStream = true;
    try {
      await refreshMonitoringStatus(notify: false, updateDss: false);
      if (irrigationProfile?.smartIrrigationEnabled ?? false) {
        await refreshIrrigation(notify: false, updateDss: false);
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

  Future<void> refreshMonitoringStatus({
    bool notify = true,
    bool updateDss = true,
  }) async {
    try {
      final status = await _client.fetchMonitoringStatus();
      monitoringStatus = status;
      latestReading = status.latest ?? latestReading;
      if (updateDss) {
        await refreshDss(notify: false);
      }
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

  Future<void> refreshTrends({
    bool notify = true,
    bool updateDss = true,
  }) async {
    try {
      trends = await _client.fetchTrends();
      if (updateDss) {
        await refreshDss(notify: false);
      }
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

  Future<void> refreshIrrigation({
    bool notify = true,
    bool updateDss = true,
  }) async {
    try {
      if (irrigationPresets.isEmpty) {
        irrigationPresets = await _client.fetchIrrigationPresets();
      }
      irrigationProfile = await _client.fetchIrrigationProfile();
      latestIrrigationAdvisory = irrigationProfile!.smartIrrigationEnabled
          ? await _client.fetchLatestIrrigationAdvisory()
          : null;
      if (updateDss) {
        await refreshDss(notify: false);
      }
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
    final inFlight = _dssRefreshInFlight;
    if (inFlight != null) {
      await inFlight;
      if (notify) {
        notifyListeners();
      }
      return;
    }

    final refresh = _refreshDssInternal();
    _dssRefreshInFlight = refresh;
    await refresh;
    if (identical(_dssRefreshInFlight, refresh)) {
      _dssRefreshInFlight = null;
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _refreshDssInternal() async {
    try {
      if (dssCropProfiles.isEmpty) {
        dssCropProfiles = await _dssCropRepository.loadProfiles();
      }
      if (cropTimelines.isEmpty) {
        cropTimelines = await _timelineRepository.load();
      }

      // Resolve the selected timeline and auto-compute the current stage from
      // the sowing date — there is no manual stage picking anymore.
      final timeline = _timelineRepository.resolve(cropTimelines, selectedCropId);
      activeTimeline = timeline;
      selectedCropId = timeline.id;
      final das = daysAfterSowing;
      final tStage = timeline.stageForDay(das);
      final signature = [
        selectedCropId,
        sowingDate.toIso8601String(),
        latestReading?.recordedAt.toIso8601String(),
        monitoringStatus?.lastUpdated?.toIso8601String(),
        _trendsSignature(trends),
        irrigationProfile?.crop,
        irrigationProfile?.cropStage,
      ].join('|');

      if (signature == _lastDssSignature && dssAnalysis != null) {
        dssErrorMessage = null;
        return;
      }

      // Crop-level agronomy from the knowledge base; stage targets from timeline.
      final crop = _dssCropRepository.resolveCrop(dssCropProfiles, timeline.kbName);
      final stage = _stageFromTimeline(tStage);
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
          daysAfterSowing: das,
          cycleDays: timeline.totalDays,
          pastHarvest: timeline.isPastHarvest(das),
        ),
      );
      dssErrorMessage = null;
      _lastDssSignature = signature;
    } catch (error) {
      dssErrorMessage = error.toString();
    }
  }

  String _trendsSignature(StationTrends? value) {
    if (value == null) return '';
    final parts = <String>['${value.hours}'];
    final keys = value.series.keys.toList()..sort();
    for (final key in keys) {
      final points = value.series[key] ?? const <TrendPoint>[];
      final last = points.isEmpty ? null : points.last.timestamp;
      parts.add('$key:${points.length}:${last?.toIso8601String() ?? ''}');
    }
    return parts.join(',');
  }

  DssCropStage _stageFromTimeline(TimelineStage s) {
    return DssCropStage(
      name: s.name,
      moistureLower: s.moistureLower,
      moistureUpper: s.moistureUpper,
      sensitivity: s.sensitivity,
      nDemand: s.nDemand,
      pDemand: s.pDemand,
      kDemand: s.kDemand,
      actionNote: s.focus,
      startDay: s.startDay,
      endDay: s.endDay,
      tempOptMin: s.tempOptMin,
      tempOptMax: s.tempOptMax,
      icon: s.icon,
    );
  }

  /// Change the selected crop (by timeline id) and rebuild the advisory.
  Future<void> setCrop(String cropId) async {
    if (cropId == selectedCropId) return;
    selectedCropId = cropId;
    await refreshDss(notify: false);
    notifyListeners();
  }

  /// Change the sowing date (auto-recomputes the growth stage) and rebuild.
  Future<void> setSowingDate(DateTime date) async {
    final normalized = DateTime(date.year, date.month, date.day);
    if (normalized == sowingDate) return;
    sowingDate = normalized;
    await refreshDss(notify: false);
    notifyListeners();
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
