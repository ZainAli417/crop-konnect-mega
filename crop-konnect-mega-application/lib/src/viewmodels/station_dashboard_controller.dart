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
import '../models/farm.dart';
import '../models/soil_sample.dart';
import '../models/soil_weather_advisory.dart';
import '../services/dss_crop_repository.dart';
import '../services/crop_timeline_repository.dart';
import '../services/dss_engine.dart';
import '../services/soil_sample_repository.dart';
import '../services/soil_weather_advisory_service.dart';
import '../services/station_data_source.dart';
import '../services/station_live_stream.dart';
import '../models/gps_reading.dart';

/// Where the DSS request should take its soil values from.
enum SoilDataSource {
  /// Use the live soil-sensor block the station is reporting (existing
  /// behaviour — the payload is unchanged).
  defaultSensor,

  /// Use a soil sample recorded with the C-type probe instead.
  recordedSample,
}

class StationDashboardController extends ChangeNotifier {
  StationDashboardController({
    required StationDataSource client,
    StationLiveStream? liveStream,
    Farm? farm,
  })  : _client = client,
        _liveStream = liveStream,
        farm = farm ?? FarmCatalog.primary {
    advisoryFarm = this.farm;
    advisoryWeatherStation = this.farm.primaryLogger;
  }

  final StationDataSource _client;
  final StationLiveStream? _liveStream;

  /// The farm backing this shell. Re-resolved by [syncFarms] once the farm
  /// list loads from Supabase.
  Farm farm;

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


  // ── Remote soil-weather advisory (DSS tab) ────────────────────────────────
  // The advisory tab has its own selection (independent of the local DSS that
  // still feeds the dashboard). Nothing is chosen by default — the user picks a
  // crop, a sowing date and a language, then taps "Get Decision".
  SoilWeatherAdvisory? soilWeatherAdvisory;
  String? soilWeatherError;
  bool isLoadingAdvisory = false;
  String? advisoryCropId; // null = not chosen
  DateTime? advisorySowingDate; // null = not chosen
  // Advisory language: 'en' | 'ur'.
  String advisoryLanguage = 'en';

  // ── Advisory context: farm, weather station and soil data source ──────────
  // The farm and weather station scope *which* readings the advisory is built
  // from; the soil data source decides whether the soil block comes from the
  // live sensor (unchanged payload) or from a recorded soil sample.
  late Farm advisoryFarm;
  late FarmLogger? advisoryWeatherStation;
  SoilDataSource advisorySoilDataSource = SoilDataSource.defaultSensor;
  SoilSample? advisorySoilSample;

  /// Soil samples recorded for [advisoryFarm], newest-first.
  List<SoilSample> soilSamples = const <SoilSample>[];
  bool isLoadingSoilSamples = false;
  String? soilSamplesError;

  /// True once the advisory has enough source data to submit. When the user
  /// chose a recorded sample, the crop/sowing values are read from that sample
  /// instead of the manual DSS selectors.
  bool get canRequestAdvisory {
    final sample = advisorySoilSample;
    final sourceCropId = advisorySoilDataSource == SoilDataSource.recordedSample
        ? (sample?.cropId.isNotEmpty == true ? sample!.cropId : advisoryCropId)
        : advisoryCropId;
    final sourceSowingDate = advisorySoilDataSource == SoilDataSource.recordedSample
        ? (sample != null && sample.sowingDate.isNotEmpty
            ? _parseSampleDate(sample.sowingDate)
            : advisorySowingDate)
        : advisorySowingDate;

    return sourceCropId != null &&
        sourceSowingDate != null &&
        (advisorySoilDataSource == SoilDataSource.defaultSensor ||
            sample != null);
  }

  /// Resolved timeline for the advisory-tab crop (null until a crop is chosen).
  CropTimeline? get advisoryTimeline {
    final id = advisoryCropId;
    if (id == null || cropTimelines.isEmpty) return null;
    return _timelineRepository.resolve(cropTimelines, id);
  }

  /// Whole days since the advisory-tab sowing date (0 if none / negative).
  int get advisoryDaysAfterSowing {
    final sown = advisorySowingDate;
    if (sown == null) return 0;
    final diff = DateTime.now().difference(sown).inHours / 24.0;
    return diff < 0 ? 0 : diff.floor();
  }

  int get advisoryStageIndex {
    final t = advisoryTimeline;
    if (t == null || t.stages.isEmpty) return 0;
    return t.stageIndexForDay(advisoryDaysAfterSowing);
  }

  bool get advisoryIsPastHarvest =>
      advisoryTimeline?.isPastHarvest(advisoryDaysAfterSowing) ?? false;

  // ── Crop stage timeline (sowing-date driven) ──────────────────────────────
  List<CropTimeline> cropTimelines = const <CropTimeline>[];
  CropTimeline? activeTimeline;
  String selectedCropId = 'wheat';
  // Default to a mid-season sowing so the timeline reads as live on first open.
  DateTime sowingDate = DateTime.now().subtract(const Duration(days: 75));

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
  final SoilWeatherAdvisoryService _advisoryService =
      SoilWeatherAdvisoryService();
  final SoilSampleRepository _soilSampleRepository = const SoilSampleRepository();
  Future<void>? _advisoryRefreshInFlight;

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
      final timeline =
          _timelineRepository.resolve(cropTimelines, selectedCropId);
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
      final crop =
          _dssCropRepository.resolveCrop(dssCropProfiles, timeline.kbName);
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

  /// Fetch the advisory for the chosen crop, sowing date, language and latest
  /// field reading. Called when the user taps "Get Decision" (and on pull-to-
  /// refresh). No-op until a crop and sowing date are selected. De-duplicates
  /// concurrent calls.
  Future<void> refreshSoilWeatherAdvisory({bool notify = true}) async {
    if (!canRequestAdvisory) {
      return;
    }
    final inFlight = _advisoryRefreshInFlight;
    if (inFlight != null) {
      await inFlight;
      if (notify) {
        notifyListeners();
      }
      return;
    }

    final refresh = _refreshAdvisoryInternal(notify: notify);
    _advisoryRefreshInFlight = refresh;
    await refresh;
    if (identical(_advisoryRefreshInFlight, refresh)) {
      _advisoryRefreshInFlight = null;
    }
  }

  Future<void> _refreshAdvisoryInternal({required bool notify}) async {
    final sample = advisorySoilDataSource == SoilDataSource.recordedSample
        ? advisorySoilSample
        : null;

    final resolvedCropId = sample != null && sample.cropId.isNotEmpty
        ? sample.cropId
        : advisoryCropId;
    final resolvedSowingDate = sample != null && sample.sowingDate.isNotEmpty
        ? _parseSampleDate(sample.sowingDate)
        : advisorySowingDate;

    if (resolvedCropId == null || resolvedSowingDate == null) return;

    isLoadingAdvisory = true;
    if (notify) {
      notifyListeners();
    }
    try {
      if (cropTimelines.isEmpty) {
        cropTimelines = await _timelineRepository.load();
      }
      final timeline = _timelineRepository.resolve(cropTimelines, resolvedCropId);

      soilWeatherAdvisory = await _advisoryService.fetchAdvisory(
        cropName: timeline.id,
        sowingDate: resolvedSowingDate,
        observationDate: DateTime.now(),
        language: advisoryLanguage,
        reading: latestReading,
        soilSample: sample,
      );
      soilWeatherError = null;
    } catch (error) {
      soilWeatherError = error.toString();
    } finally {
      isLoadingAdvisory = false;
      if (notify) {
        notifyListeners();
      }
    }
  }

  static DateTime? _parseSampleDate(String value) {
    if (value.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
    return null;
  }

  /// Choose the advisory crop (by timeline id). Loads timelines if needed and
  /// clears any stale advisory so the user re-runs the decision.
  Future<void> setAdvisoryCrop(String cropId) async {
    if (cropTimelines.isEmpty) {
      try {
        cropTimelines = await _timelineRepository.load();
      } catch (_) {
        // Keep the selection; the fetch will surface any load error.
      }
    }
    advisoryCropId = cropId;
    soilWeatherAdvisory = null;
    soilWeatherError = null;
    notifyListeners();
  }

  /// Choose the advisory sowing date. Clears any stale advisory.
  void setAdvisorySowingDate(DateTime date) {
    advisorySowingDate = DateTime(date.year, date.month, date.day);
    soilWeatherAdvisory = null;
    soilWeatherError = null;
    notifyListeners();
  }

  /// Make sure the bundled crop timelines are loaded (used by the crop pickers
  /// on screens that open before the first DSS refresh).
  Future<void> ensureCropTimelines() async {
    if (cropTimelines.isNotEmpty) return;
    try {
      cropTimelines = await _timelineRepository.load();
      notifyListeners();
    } catch (_) {
      // Non-fatal: the pickers show an empty state and the DSS refresh retries.
    }
  }

  /// Re-resolve every held farm/logger reference against the current
  /// [FarmCatalog], after the list has been loaded or refreshed.
  ///
  /// Ids that no longer exist fall back to the primary farm and its logger, so
  /// [farm], [advisoryFarm] and any dropdown value stay valid — this is what
  /// keeps a stale id from producing a null or an out-of-range dropdown.
  void syncFarms() {
    farm = FarmCatalog.resolve(farm.id);

    final resolvedAdvisoryFarm = FarmCatalog.resolve(advisoryFarm.id);
    final farmChanged = resolvedAdvisoryFarm.id != advisoryFarm.id;
    advisoryFarm = resolvedAdvisoryFarm;

    // Keep the selected logger only if it still belongs to this farm.
    final loggers = advisoryFarm.loggers;
    final currentLoggerId = advisoryWeatherStation?.id;
    FarmLogger? resolvedLogger;
    for (final logger in loggers) {
      if (logger.id == currentLoggerId) {
        resolvedLogger = logger;
        break;
      }
    }
    advisoryWeatherStation = resolvedLogger ?? advisoryFarm.primaryLogger;

    // A different farm means the loaded samples and any picked sample belong to
    // something else now.
    if (farmChanged) {
      advisorySoilSample = null;
      soilSamples = const <SoilSample>[];
      soilWeatherAdvisory = null;
      soilWeatherError = null;
    }

    notifyListeners();
  }

  /// Choose which farm the advisory is being built for. Resets the weather
  /// station to that farm's logger and drops any farm-specific sample choice.
  void setAdvisoryFarm(Farm value) {
    if (value.id == advisoryFarm.id) return;
    advisoryFarm = value;
    advisoryWeatherStation = value.primaryLogger;
    advisorySoilSample = null;
    soilSamples = const <SoilSample>[];
    soilWeatherAdvisory = null;
    soilWeatherError = null;
    notifyListeners();
    if (advisorySoilDataSource == SoilDataSource.recordedSample) {
      unawaited(loadSoilSamples());
    }
  }

  /// Choose which weather station / logger the advisory reads from.
  void setAdvisoryWeatherStation(FarmLogger value) {
    if (value.id == advisoryWeatherStation?.id) return;
    advisoryWeatherStation = value;
    soilWeatherAdvisory = null;
    soilWeatherError = null;
    notifyListeners();
  }

  /// Switch between the live soil sensor and a recorded soil sample. Selecting
  /// the recorded-sample option pulls the farm's samples in the background.
  void setAdvisorySoilDataSource(SoilDataSource value) {
    if (value == advisorySoilDataSource) return;
    advisorySoilDataSource = value;
    if (value == SoilDataSource.defaultSensor) {
      advisorySoilSample = null;
    }
    soilWeatherAdvisory = null;
    soilWeatherError = null;
    notifyListeners();
    if (value == SoilDataSource.recordedSample && soilSamples.isEmpty) {
      unawaited(loadSoilSamples());
    }
  }

  /// Pick the recorded sample whose soil values replace the live sensor block.
  /// When a sample is chosen, its crop + sowing metadata become the advisory
  /// request values so the DSS no longer reuses the default selector state.
  void setAdvisorySoilSample(SoilSample? value) {
    advisorySoilSample = value;
    if (value != null) {
      if (value.cropId.isNotEmpty) {
        advisoryCropId = value.cropId;
      }
      final sampleSowingDate = _parseSampleDate(value.sowingDate);
      if (sampleSowingDate != null) {
        advisorySowingDate = sampleSowingDate;
      }
    }
    soilWeatherAdvisory = null;
    soilWeatherError = null;
    notifyListeners();
  }

  /// Load the soil samples recorded for [advisoryFarm] (newest-first).
  Future<void> loadSoilSamples({bool notify = true}) async {
    isLoadingSoilSamples = true;
    soilSamplesError = null;
    if (notify) {
      notifyListeners();
    }
    try {
      soilSamples = await _soilSampleRepository.fetchSamples(
        farmId: advisoryFarm.id,
      );
      // Drop a selection that no longer exists in the refreshed list.
      final selectedId = advisorySoilSample?.id;
      if (selectedId != null &&
          !soilSamples.any((sample) => sample.id == selectedId)) {
        advisorySoilSample = null;
      }
    } catch (error) {
      soilSamplesError = error.toString();
    } finally {
      isLoadingSoilSamples = false;
      if (notify) {
        notifyListeners();
      }
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

  /// Change the selected crop (by timeline id) and rebuild the local advisory.
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

  /// Switch the advisory language ('en' | 'ur'). Clears any stale advisory so
  /// the user re-runs the decision in the new language.
  void setAdvisoryLanguage(String language) {
    if (language == advisoryLanguage) return;
    advisoryLanguage = language;
    soilWeatherAdvisory = null;
    soilWeatherError = null;
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
    final sensors = sensorKey == 'wind'
        ? <String, bool>{
            'wind_speed': enabled,
            'wind_direction': enabled,
          }
        : <String, bool>{sensorKey: enabled};
    await patchSettings(
      StationSettingsPatch(
        sensorEnabled: sensors,
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

  Future<void> updateSensorInterval(
      String sensorKey, int intervalSeconds) async {
    final normalizedKey = sensorKey == 'solar' ? 'uv' : sensorKey;
    await patchSettings(
      StationSettingsPatch(
        sensorIntervals: <String, int>{normalizedKey: intervalSeconds},
      ),
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
