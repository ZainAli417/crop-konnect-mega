import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../config/app_config.dart';
import '../models/irrigation.dart';
import '../models/monitoring_status.dart';
import '../models/sensor_reading.dart';
import '../models/station_settings.dart';
import '../models/station_summary.dart';
import '../models/station_trends.dart';
import '../models/gps_reading.dart';
import 'platform_http_client.dart';
import 'station_data_source.dart';

class SupabaseStationDataSource implements StationDataSource {
  SupabaseStationDataSource({
    required String supabaseUrl,
    required String anonKey,
    required String deviceId,
    required String stationName,
    http.Client? httpClient,
  })  : _baseUrl = _normalizeBaseUrl(supabaseUrl),
        _anonKey = anonKey,
        _deviceId = deviceId,
        _stationName = stationName,
        _httpClient = httpClient ?? createPlatformHttpClient();

  static const String _readingSelect =
      'id,station_id,recorded_at,received_at,wind_speed,wind_direction_degrees,'
      'wind_direction_label,soil_moisture,soil_temperature,soil_ec,'
      'soil_nitrogen,soil_phosphorus,soil_potassium,soil_ph,rainfall,'
      'solar_radiation,stations!inner(device_id,name)';

  final String _baseUrl;
  final String _anonKey;
  final String _deviceId;
  final String _stationName;
  final http.Client _httpClient;

  _StationRef? _station;
  Map<String, Map<String, _CropStagePreset>>? _presetCache;
  sb.RealtimeChannel? _realtimeChannel;
  StreamController<SensorReading>? _realtimeController;

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'/$'), '');
    if (trimmed.endsWith('/rest/v1')) {
      return trimmed.substring(0, trimmed.length - '/rest/v1'.length);
    }
    return trimmed;
  }

  @override
  AppDataMode get mode => AppDataMode.supabase;

  @override
  String get modeLabel => 'Supabase Cloud';

  @override
  Future<SensorReading> fetchLatestReading() async {
    final rows = await _getList(
      _restUri('sensor_readings', <String, String>{
        'select': _readingSelect,
        'stations.device_id': 'eq.$_deviceId',
        'order': 'recorded_at.desc',
        'limit': '1',
      }),
    );
    if (rows.isEmpty) {
      throw StateError('No readings found for $_deviceId in Supabase.');
    }
    return _readingFromRow(rows.first);
  }

  @override
  Future<GpsReading?> fetchLatestGpsReading() async {
    try {
      final station = await _fetchStation();
      final uri = _restUri('gps_readings', <String, String>{
        'select': '*',
        'station_id': 'eq.${station.id}',
        'order': 'recorded_at.desc',
        'limit': '1',
      });
      final rows = await _getList(uri);
      if (rows.isEmpty) {
        return null;
      }
      final reading = GpsReading.fromJson(rows.first);
      return reading;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<StationSummary> fetchSummary({int hours = 24}) async {
    final rows = await _fetchReadings(hours: hours, ascending: false);
    DateTime? lastRecordedAt;
    if (rows.isNotEmpty) {
      lastRecordedAt = rows
          .map((row) => _parseDateTime(row['recorded_at']))
          .whereType<DateTime>()
          .fold<DateTime?>(null, (latest, value) {
        if (latest == null || value.isAfter(latest)) {
          return value;
        }
        return latest;
      });
    }

    return StationSummary(
      deviceId: _deviceId,
      hours: hours,
      totalReadings: rows.length,
      lastRecordedAt: lastRecordedAt,
      averages: <String, double?>{
        'ws': _average(rows, 'wind_speed'),
        'moist': _average(rows, 'soil_moisture'),
        'temp': _average(rows, 'soil_temperature'),
        'rain': _average(rows, 'rainfall'),
        'solar': _average(rows, 'solar_radiation'),
      },
    );
  }

  @override
  Future<MonitoringStatus> fetchMonitoringStatus() async {
    final latest = await fetchLatestReading();
    StationSettings? settings;
    try {
      settings = await fetchSettings();
    } catch (_) {
      settings = null;
    }

    final conditions = _buildConditions(latest);
    final health = _buildSensorHealth(latest, settings);
    final alerts = _buildAlerts(latest, health, conditions);

    return MonitoringStatus(
      deviceId: latest.deviceId,
      stationName: latest.stationName,
      lastUpdated: latest.recordedAt,
      overallStatus: alerts.any((alert) => alert.severity == 'critical')
          ? 'critical'
          : alerts.any((alert) => alert.severity == 'warning')
              ? 'attention'
              : 'normal',
      sensorHealth: health,
      conditions: conditions,
      alerts: alerts,
      latest: latest,
    );
  }

  @override
  Future<StationTrends> fetchTrends({int hours = 24}) async {
    final rows = await _fetchReadings(hours: hours, ascending: true);

    List<TrendPoint> seriesFor(String key) {
      return rows.map((row) {
        return TrendPoint(
          timestamp: _parseDateTime(row['recorded_at']) ?? DateTime.now(),
          value: _asDouble(row[key]),
        );
      }).toList();
    }

    return StationTrends(
      deviceId: _deviceId,
      hours: hours,
      series: <String, List<TrendPoint>>{
        'moist': seriesFor('soil_moisture'),
        'temp': seriesFor('soil_temperature'),
        'rain': seriesFor('rainfall'),
        'ws': seriesFor('wind_speed'),
        'uv': seriesFor('solar_radiation'),
        'ec': seriesFor('soil_ec'),
        'ph': seriesFor('soil_ph'),
        'n': seriesFor('soil_nitrogen'),
        'p': seriesFor('soil_phosphorus'),
        'k': seriesFor('soil_potassium'),
      },
    );
  }

  @override
  Future<StationSettings> fetchSettings() async {
    final station = await _fetchStation();
    final row = await _fetchSettingsRow(station);
    if (row == null) {
      return _defaultSettings(station);
    }
    return _settingsFromRow(row, station);
  }

  @override
  Future<StationSettings> patchSettings(StationSettingsPatch patch) async {
    final station = await _fetchStation();
    final existingRow = await _fetchSettingsRow(station);
    final payload = _settingsPatchPayload(patch, existingRow: existingRow);
    if (payload.isEmpty) {
      return fetchSettings();
    }

    final rows = await _sendList(
      'POST',
      _restUri('station_settings', const <String, String>{
        'on_conflict': 'station_id',
      }),
      <String, dynamic>{
        'station_id': station.id,
        ...payload,
      },
      prefer: 'resolution=merge-duplicates,return=representation',
    );

    if (rows.isEmpty) {
      return fetchSettings();
    }
    return _settingsFromRow(rows.first, station);
  }

  Future<Map<String, dynamic>?> _fetchSettingsRow(_StationRef station) async {
    final rows = await _getList(
      _restUri('station_settings', <String, String>{
        'select': '*',
        'station_id': 'eq.${station.id}',
        'limit': '1',
      }),
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  @override
  Future<List<IrrigationCropOption>> fetchIrrigationPresets() async {
    final presets = await _loadPresets();
    return presets.entries
        .map(
          (entry) => IrrigationCropOption(
            crop: entry.key,
            stages: entry.value.keys.toList(),
          ),
        )
        .toList();
  }

  @override
  Future<IrrigationProfile> fetchIrrigationProfile() async {
    final station = await _fetchStation();
    final rows = await _getList(
      _restUri('irrigation_profiles', <String, String>{
        'select': '*',
        'station_id': 'eq.${station.id}',
        'limit': '1',
      }),
    );
    if (rows.isEmpty) {
      return _defaultIrrigationProfile(station);
    }
    return _profileFromRow(rows.first, station);
  }

  @override
  Future<IrrigationProfile> patchIrrigationProfile(
      IrrigationProfilePatch patch) async {
    final station = await _fetchStation();
    final existingRows = await _getList(
      _restUri('irrigation_profiles', <String, String>{
        'select': '*',
        'station_id': 'eq.${station.id}',
        'limit': '1',
      }),
    );
    final existing = existingRows.isEmpty
        ? await _defaultIrrigationProfile(station)
        : _profileFromRow(existingRows.first, station);

    final payload = await _irrigationPatchPayload(patch, existing);
    if (payload.isEmpty) {
      return existing;
    }

    final rows = existingRows.isEmpty
        ? await _sendList(
            'POST',
            _restUri('irrigation_profiles', const <String, String>{}),
            <String, dynamic>{
              'station_id': station.id,
              'field_name': station.name,
              ...payload,
            },
          )
        : await _sendList(
            'PATCH',
            _restUri('irrigation_profiles', <String, String>{
              'station_id': 'eq.${station.id}',
            }),
            payload,
          );

    if (rows.isEmpty) {
      return fetchIrrigationProfile();
    }
    return _profileFromRow(rows.first, station);
  }

  @override
  Future<IrrigationAdvisory?> fetchLatestIrrigationAdvisory() async {
    final station = await _fetchStation();
    final rows = await _getList(
      _restUri('irrigation_advisories', <String, String>{
        'select': '*',
        'station_id': 'eq.${station.id}',
        'order': 'generated_at.desc,id.desc',
        'limit': '1',
      }),
    );
    if (rows.isEmpty) {
      return null;
    }
    return _advisoryFromRow(rows.first, station);
  }

  Future<List<Map<String, dynamic>>> _fetchReadings({
    required int hours,
    required bool ascending,
  }) {
    final since = DateTime.now()
        .toUtc()
        .subtract(Duration(hours: hours))
        .toIso8601String();
    return _getList(
      _restUri('sensor_readings', <String, String>{
        'select': _readingSelect,
        'stations.device_id': 'eq.$_deviceId',
        'recorded_at': 'gte.$since',
        'order': 'recorded_at.${ascending ? 'asc' : 'desc'}',
        'limit': '1000',
      }),
    );
  }

  Future<_StationRef> _fetchStation() async {
    final cached = _station;
    if (cached != null) {
      return cached;
    }

    final rows = await _getList(
      _restUri('stations', <String, String>{
        'select': 'id,device_id,name',
        'device_id': 'eq.$_deviceId',
        'limit': '1',
      }),
    );
    if (rows.isEmpty) {
      throw StateError('Station $_deviceId was not found in Supabase.');
    }
    final row = rows.first;
    final station = _StationRef(
      id: (row['id'] as num).toInt(),
      deviceId: row['device_id'] as String? ?? _deviceId,
      name: row['name'] as String? ?? _stationName,
    );
    _station = station;
    return station;
  }

  Uri _restUri(String table, Map<String, String> query) {
    return Uri.parse('$_baseUrl/rest/v1/$table').replace(
      queryParameters: query.isEmpty ? null : query,
    );
  }

  Future<List<Map<String, dynamic>>> _getList(Uri uri) async {
    final response = await _httpClient.get(uri, headers: _baseHeaders());
    return _decodeListResponse(uri, response);
  }

  Future<List<Map<String, dynamic>>> _sendList(
    String method,
    Uri uri,
    Map<String, dynamic> payload, {
    String? prefer,
  }) async {
    final headers = _writeHeaders(prefer: prefer);
    final response = switch (method.toUpperCase()) {
      'PATCH' => await _httpClient.patch(
          uri,
          headers: headers,
          body: jsonEncode(payload),
        ),
      'POST' => await _httpClient.post(
          uri,
          headers: headers,
          body: jsonEncode(payload),
        ),
      _ => throw UnsupportedError('Unsupported method: $method'),
    };
    return _decodeListResponse(uri, response);
  }

  Future<List<Map<String, dynamic>>> _decodeListResponse(
    Uri uri,
    http.Response response,
  ) async {
    final body = response.body;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Supabase request failed with status ${response.statusCode}: $body ($uri)',
      );
    }
    if (body.trim().isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw FormatException('Expected Supabase list response.', body);
    }
    return decoded.whereType<Map<String, dynamic>>().toList();
  }

  Map<String, String> _baseHeaders() {
    if (_anonKey.trim().isEmpty) {
      throw StateError(
        'CROPCONNECT_SUPABASE_ANON_KEY is required for Supabase Cloud mode.',
      );
    }

    return <String, String>{
      'Accept': 'application/json',
      'apikey': _anonKey,
      'Authorization': 'Bearer $_anonKey',
    };
  }

  Map<String, String> _writeHeaders({String? prefer}) {
    return <String, String>{
      ..._baseHeaders(),
      'Content-Type': 'application/json',
      'Prefer': prefer ?? 'return=representation',
    };
  }

  SensorReading _readingFromRow(Map<String, dynamic> row) {
    final station = _stationFromNested(row);
    return SensorReading(
      id: (row['id'] as num).toInt(),
      deviceId: station.deviceId,
      stationName: station.name,
      recordedAt: _parseDateTime(row['recorded_at']) ?? DateTime.now(),
      receivedAt: _parseDateTime(row['received_at']) ?? DateTime.now(),
      ws: _asDouble(row['wind_speed']),
      wdDeg: _asDouble(row['wind_direction_degrees']),
      wdDir: row['wind_direction_label'] as String?,
      moist: _asDouble(row['soil_moisture']),
      temp: _asDouble(row['soil_temperature']),
      ec: _asDouble(row['soil_ec']),
      n: _asDouble(row['soil_nitrogen']),
      p: _asDouble(row['soil_phosphorus']),
      k: _asDouble(row['soil_potassium']),
      ph: _asDouble(row['soil_ph']),
      rain: _asDouble(row['rainfall']),
      solar: _asDouble(row['solar_radiation']),
    );
  }

  _StationRef _stationFromNested(Map<String, dynamic> row) {
    final nested = row['stations'];
    if (nested is Map<String, dynamic>) {
      return _StationRef(
        id: (row['station_id'] as num?)?.toInt() ?? _station?.id ?? 0,
        deviceId: nested['device_id'] as String? ?? _deviceId,
        name: nested['name'] as String? ?? _stationName,
      );
    }
    return _station ??
        _StationRef(id: 0, deviceId: _deviceId, name: _stationName);
  }

  StationSettings _settingsFromRow(
    Map<String, dynamic> row,
    _StationRef station,
  ) {
    return StationSettings(
      deviceId: station.deviceId,
      stationName: station.name,
      sensors: StationSensorSettings(
        windSpeedEnabled: row['wind_speed_enabled'] == true,
        windDirectionEnabled: row['wind_direction_enabled'] == true,
        soilEnabled: row['soil_enabled'] == true,
        rainEnabled: row['rain_enabled'] == true,
        uvEnabled: row['uv_enabled'] == true,
      ),
      polling: StationPollingSettings(
        pollIntervalSeconds:
            (row['poll_interval_seconds'] as num?)?.toInt() ?? 5,
        interReadDelayMs: (row['inter_read_delay_ms'] as num?)?.toInt() ?? 250,
        sensorReadOrder: _readOrderFromValue(row['sensor_read_order']),
        sensorIntervals: _sensorIntervalsFromScheduleJson(
          row['sensor_read_schedule_json'],
          enabled: <String, bool>{
            'wind': row['wind_speed_enabled'] == true ||
                row['wind_direction_enabled'] == true,
            'soil': row['soil_enabled'] == true,
            'rain': row['rain_enabled'] == true,
            'uv': row['uv_enabled'] == true,
          },
        ),
      ),
      updatedAt: _parseDateTime(row['updated_at']),
    );
  }

  StationSettings _defaultSettings(_StationRef station) {
    return StationSettings(
      deviceId: station.deviceId,
      stationName: station.name,
      sensors: const StationSensorSettings(
        windSpeedEnabled: false,
        windDirectionEnabled: false,
        soilEnabled: false,
        rainEnabled: false,
        uvEnabled: false,
      ),
      polling: const StationPollingSettings(
        pollIntervalSeconds: 5,
        interReadDelayMs: 250,
        sensorReadOrder: <String>[
          'uv',
          'wind_speed',
          'wind_direction',
          'soil',
          'rain',
        ],
        sensorIntervals: <String, SensorIntervalSettings>{
          'wind': SensorIntervalSettings(
            enabled: false,
            intervalSeconds: kDefaultSensorIntervalSeconds,
          ),
          'soil': SensorIntervalSettings(
            enabled: false,
            intervalSeconds: kDefaultSensorIntervalSeconds,
          ),
          'rain': SensorIntervalSettings(
            enabled: false,
            intervalSeconds: kDefaultSensorIntervalSeconds,
          ),
          'uv': SensorIntervalSettings(
            enabled: false,
            intervalSeconds: kDefaultSensorIntervalSeconds,
          ),
        },
      ),
      updatedAt: null,
    );
  }

  Map<String, dynamic> _settingsPatchPayload(
    StationSettingsPatch patch, {
    Map<String, dynamic>? existingRow,
  }) {
    final payload = <String, dynamic>{};

    patch.sensorEnabled?.forEach((key, enabled) {
      switch (_normalizeSensorKey(key)) {
        case 'wind':
          payload['wind_speed_enabled'] = enabled;
          payload['wind_direction_enabled'] = enabled;
          break;
        case 'wind_speed':
          payload['wind_speed_enabled'] = enabled;
          break;
        case 'wind_direction':
          payload['wind_direction_enabled'] = enabled;
          break;
        case 'soil':
          payload['soil_enabled'] = enabled;
          break;
        case 'rain':
          payload['rain_enabled'] = enabled;
          break;
        case 'uv':
          payload['uv_enabled'] = enabled;
          break;
      }
    });

    if (patch.pollIntervalSeconds != null) {
      payload['poll_interval_seconds'] = patch.pollIntervalSeconds;
    }
    if (patch.interReadDelayMs != null) {
      payload['inter_read_delay_ms'] = patch.interReadDelayMs;
    }
    if (patch.sensorReadOrder != null && patch.sensorReadOrder!.isNotEmpty) {
      payload['sensor_read_order'] =
          _normalizeReadOrder(patch.sensorReadOrder!).join(',');
    }
    if (patch.sensorIntervals != null && patch.sensorIntervals!.isNotEmpty) {
      payload['sensor_read_schedule_json'] = _mergedSensorIntervalsJson(
        existingRow?['sensor_read_schedule_json'],
        patch.sensorIntervals!,
      );
    }

    if (payload.isNotEmpty) {
      payload['updated_at'] = DateTime.now().toUtc().toIso8601String();
    }
    return payload;
  }

  Map<String, dynamic> _decodeSensorSchedule(dynamic raw) {
    dynamic decoded = raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        decoded = null;
      }
    }
    if (decoded is! Map) {
      return <String, dynamic>{};
    }
    return decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  Map<String, SensorIntervalSettings> _sensorIntervalsFromScheduleJson(
    dynamic raw, {
    Map<String, bool> enabled = const <String, bool>{},
  }) {
    final intervals = <String, SensorIntervalSettings>{
      'wind': SensorIntervalSettings(
        enabled: enabled['wind'] ?? false,
        intervalSeconds: kDefaultSensorIntervalSeconds,
      ),
      'soil': SensorIntervalSettings(
        enabled: enabled['soil'] ?? false,
        intervalSeconds: kDefaultSensorIntervalSeconds,
      ),
      'rain': SensorIntervalSettings(
        enabled: enabled['rain'] ?? false,
        intervalSeconds: kDefaultSensorIntervalSeconds,
      ),
      'uv': SensorIntervalSettings(
        enabled: enabled['uv'] ?? false,
        intervalSeconds: kDefaultSensorIntervalSeconds,
      ),
    };
    final decoded = _decodeSensorSchedule(raw);
    if (decoded.isEmpty) {
      return intervals;
    }
    decoded.forEach((rawKey, rawValue) {
      if (rawValue is! Map) return;
      final key = _normalizeIntervalKey(rawKey.toString());
      if (!intervals.containsKey(key)) return;
      final intervalSeconds = _intervalSecondsFromScheduleItem(rawValue);
      intervals[key] = SensorIntervalSettings(
        enabled: enabled[key] ?? false,
        intervalSeconds: intervalSeconds ?? kDefaultSensorIntervalSeconds,
      );
    });
    return intervals;
  }

  String _mergedSensorIntervalsJson(
    dynamic existingSchedule,
    Map<String, int> sensorIntervals,
  ) {
    final plan = _decodeSensorSchedule(existingSchedule);
    sensorIntervals.forEach((rawKey, intervalSeconds) {
      final key = _normalizeIntervalKey(rawKey);
      final readsPerDay = _readsPerDayFromIntervalSeconds(intervalSeconds);
      final item = <String, dynamic>{
        'mode': 'reads_per_day',
        'reads_per_day': readsPerDay,
      };
      if (key == 'wind') {
        plan['wind_speed'] = item;
        plan['wind_direction'] = Map<String, dynamic>.from(item);
      } else {
        plan[key] = item;
      }
    });
    return jsonEncode(plan);
  }

  String _normalizeIntervalKey(String value) {
    final key = value.trim().toLowerCase();
    if (key == 'wind' ||
        key == 'wind_sensor' ||
        key == 'wind_speed' ||
        key == 'wind_direction') {
      return 'wind';
    }
    return key == 'solar' ? 'uv' : key;
  }

  int _readsPerDayFromIntervalSeconds(int intervalSeconds) {
    final safeInterval = intervalSeconds < 1 ? 1 : intervalSeconds;
    final reads = (86400 / safeInterval).round();
    return reads < 1 ? 1 : reads;
  }

  int? _intervalSecondsFromScheduleItem(Map<dynamic, dynamic> item) {
    final rawInterval = item['interval_seconds'];
    if (rawInterval is num && rawInterval > 0) {
      return rawInterval.toInt();
    }
    final rawReads = item['reads_per_day'];
    if (rawReads is num && rawReads > 0) {
      return (86400 / rawReads).round();
    }
    return null;
  }

  IrrigationProfile _profileFromRow(
    Map<String, dynamic> row,
    _StationRef station,
  ) {
    return IrrigationProfile.fromJson(<String, dynamic>{
      ...row,
      'device_id': station.deviceId,
      'station_name': station.name,
    });
  }

  Future<IrrigationProfile> _defaultIrrigationProfile(
      _StationRef station) async {
    final presets = await _loadPresets();
    final crop = presets.keys.isNotEmpty ? presets.keys.first : 'Wheat';
    final stages = presets[crop] ?? const <String, _CropStagePreset>{};
    final stage = stages.keys.isNotEmpty ? stages.keys.first : 'Vegetative';
    final preset = stages[stage];

    return IrrigationProfile(
      id: 0,
      deviceId: station.deviceId,
      stationName: station.name,
      crop: crop,
      cropStage: stage,
      smartIrrigationEnabled: false,
      moistureLowerTarget: preset?.lower ?? 35,
      moistureUpperTarget: preset?.upper ?? 65,
      effectiveRainMm: 2,
      rainWindowHours: 6,
      highTempC: 35,
      highSolarWm2: 700,
      highWindMs: 6,
      staleAfterMinutes: 15,
      updatedAt: null,
    );
  }

  Future<Map<String, dynamic>> _irrigationPatchPayload(
    IrrigationProfilePatch patch,
    IrrigationProfile existing,
  ) async {
    final payload = <String, dynamic>{};
    if (patch.smartIrrigationEnabled != null) {
      payload['smart_irrigation_enabled'] = patch.smartIrrigationEnabled;
    }

    final shouldApplyPreset = patch.crop != null ||
        patch.cropStage != null ||
        patch.smartIrrigationEnabled == true;
    if (shouldApplyPreset) {
      final cropValue = patch.crop ?? existing.crop;
      final stageValue = patch.cropStage ?? existing.cropStage;
      final preset = await _findPreset(cropValue, stageValue);
      payload.addAll(<String, dynamic>{
        'crop': preset.crop,
        'crop_stage': preset.stage,
        'soil_type': 'System Preset',
        'irrigation_method': 'System Managed',
        'moisture_lower_target': preset.lower,
        'moisture_upper_target': preset.upper,
        'effective_rain_mm': 2,
        'rain_window_hours': 6,
        'high_temp_c': 35,
        'high_solar_wm2': 700,
        'high_wind_ms': 6,
        'stale_after_minutes': 15,
      });
      payload['smart_irrigation_enabled'] =
          patch.smartIrrigationEnabled ?? true;
    }

    if (payload.isNotEmpty) {
      payload['updated_at'] = DateTime.now().toUtc().toIso8601String();
    }
    return payload;
  }

  IrrigationAdvisory _advisoryFromRow(
    Map<String, dynamic> row,
    _StationRef station,
  ) {
    return IrrigationAdvisory.fromJson(<String, dynamic>{
      'id': row['id'],
      'device_id': station.deviceId,
      'station_name': station.name,
      'reading_id': row['reading_id'],
      'generated_at': row['generated_at'],
      'decision': row['decision'],
      'urgency': row['urgency'],
      'data_status': row['data_status'],
      'title': row['title'],
      'message': row['message'],
      'reason': row['reason'],
      'condition_summary': row['condition_summary'],
      'factors': _jsonObject(row['factors_json']),
      'profile_snapshot': _jsonObject(row['profile_snapshot_json']),
    });
  }

  Future<Map<String, Map<String, _CropStagePreset>>> _loadPresets() async {
    final cached = _presetCache;
    if (cached != null) {
      return cached;
    }

    final raw = await rootBundle.loadString('assets/crop_moisture_ranges.json');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid crop moisture preset file.');
    }

    final presets = <String, Map<String, _CropStagePreset>>{};
    decoded.forEach((key, value) {
      if (value is! Map<String, dynamic>) {
        return;
      }
      final crop = (value['crop'] as String? ?? key).trim();
      final stages = value['stages'];
      if (crop.isEmpty || stages is! List) {
        return;
      }
      final cropStages = <String, _CropStagePreset>{};
      for (final item in stages) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final stage = (item['stage'] as String? ?? '').trim();
        final lower = _asDouble(item['lower_moisture']);
        final upper = _asDouble(item['upper_moisture']);
        if (stage.isEmpty ||
            lower == null ||
            upper == null ||
            lower < 0 ||
            upper > 100 ||
            lower >= upper) {
          continue;
        }
        cropStages[stage] = _CropStagePreset(
          crop: crop,
          stage: stage,
          lower: lower,
          upper: upper,
        );
      }
      if (cropStages.isNotEmpty) {
        presets[crop] = cropStages;
      }
    });

    if (presets.isEmpty) {
      throw const FormatException('No crop moisture presets were loaded.');
    }
    _presetCache = presets;
    return presets;
  }

  Future<_CropStagePreset> _findPreset(String crop, String stage) async {
    final presets = await _loadPresets();
    final normalizedCrop = _normalizeOption(crop);
    for (final cropEntry in presets.entries) {
      if (_normalizeOption(cropEntry.key) != normalizedCrop) {
        continue;
      }
      final normalizedStage = _normalizeOption(stage);
      for (final stageEntry in cropEntry.value.entries) {
        if (_normalizeOption(stageEntry.key) == normalizedStage) {
          return stageEntry.value;
        }
      }
      throw StateError(
        'Unsupported stage "$stage" for ${cropEntry.key}.',
      );
    }
    throw StateError('Unsupported crop "$crop".');
  }

  Map<String, String> _buildConditions(SensorReading reading) {
    return <String, String>{
      'soil_moisture': reading.moist == null
          ? 'unknown'
          : reading.moist! < 20
              ? 'low'
              : reading.moist! > 60
                  ? 'high'
                  : 'normal',
      'temperature': reading.temp == null
          ? 'unknown'
          : reading.temp! > 35
              ? 'hot'
              : reading.temp! < 15
                  ? 'cool'
                  : 'normal',
      'rain': reading.rain != null && reading.rain! > 0
          ? 'detected'
          : 'not_detected',
      'wind': reading.ws == null
          ? 'unknown'
          : reading.ws! > 10
              ? 'high'
              : reading.ws! > 5
                  ? 'moderate'
                  : 'calm',
      'uv': reading.solar == null
          ? 'unknown'
          : reading.solar! > 700
              ? 'high'
              : reading.solar! > 300
                  ? 'moderate'
                  : 'low',
      'ec': reading.ec == null
          ? 'unknown'
          : reading.ec! > 1800
              ? 'high'
              : 'normal',
    };
  }

  Map<String, SensorHealth> _buildSensorHealth(
    SensorReading reading,
    StationSettings? settings,
  ) {
    final isStale =
        DateTime.now().difference(reading.recordedAt).inMinutes > 10;

    SensorHealth health(bool enabled) {
      if (!enabled) {
        return const SensorHealth(
          status: 'disabled',
          freshness: 'disabled',
          lastUpdated: null,
        );
      }
      return SensorHealth(
        status: isStale ? 'stale' : 'online',
        freshness: isStale ? 'stale' : 'fresh',
        lastUpdated: reading.recordedAt,
      );
    }

    final sensors = settings?.sensors;
    return <String, SensorHealth>{
      'wind': health(
        (sensors?.windSpeedEnabled ?? false) ||
            (sensors?.windDirectionEnabled ?? false),
      ),
      'soil': health(sensors?.soilEnabled ?? false),
      'rain': health(sensors?.rainEnabled ?? false),
      'uv': health(sensors?.uvEnabled ?? false),
    };
  }

  List<MonitoringAlert> _buildAlerts(
    SensorReading reading,
    Map<String, SensorHealth> health,
    Map<String, String> conditions,
  ) {
    final alerts = <MonitoringAlert>[];

    if (health.values.any((item) => item.freshness == 'stale')) {
      alerts.add(
        MonitoringAlert(
          type: 'stale_data',
          severity: 'warning',
          title: 'Data delay detected',
          message: 'Latest cloud reading is older than the freshness window.',
          timestamp: reading.recordedAt,
        ),
      );
    }
    if (conditions['soil_moisture'] == 'low') {
      alerts.add(
        MonitoringAlert(
          type: 'low_moisture',
          severity: 'warning',
          title: 'Low soil moisture',
          message: 'Soil moisture is below the basic monitoring threshold.',
          timestamp: reading.recordedAt,
        ),
      );
    }
    if (conditions['temperature'] == 'hot') {
      alerts.add(
        MonitoringAlert(
          type: 'high_temperature',
          severity: 'warning',
          title: 'High soil temperature',
          message: 'Soil temperature is elevated and may increase crop stress.',
          timestamp: reading.recordedAt,
        ),
      );
    }
    if (conditions['rain'] == 'detected') {
      alerts.add(
        MonitoringAlert(
          type: 'rain_detected',
          severity: 'info',
          title: 'Rain detected',
          message: 'Rainfall is present in the latest cloud reading.',
          timestamp: reading.recordedAt,
        ),
      );
    }
    if (conditions['wind'] == 'high') {
      alerts.add(
        MonitoringAlert(
          type: 'high_wind',
          severity: 'warning',
          title: 'High wind speed',
          message: 'Wind speed is high and should be watched for operations.',
          timestamp: reading.recordedAt,
        ),
      );
    }
    return alerts;
  }

  double? _average(List<Map<String, dynamic>> rows, String key) {
    final values = rows.map((row) => _asDouble(row[key])).whereType<double>();
    if (values.isEmpty) {
      return null;
    }
    final total = values.fold<double>(0, (sum, value) => sum + value);
    return double.parse((total / values.length).toStringAsFixed(2));
  }

  List<String> _readOrderFromValue(dynamic value) {
    final order = _normalizeReadOrder(_csv(value));
    if (order.isEmpty) {
      return const <String>[
        'uv',
        'wind_speed',
        'wind_direction',
        'soil',
        'rain',
      ];
    }
    return order;
  }

  List<String> _normalizeReadOrder(Iterable<String> values) {
    final order = <String>[];

    void add(String key) {
      if (key.isNotEmpty && !order.contains(key)) {
        order.add(key);
      }
    }

    for (final value in values) {
      final key = _normalizeSensorKey(value);
      if (key == 'wind') {
        add('wind_speed');
        add('wind_direction');
      } else {
        add(key);
      }
    }

    return order;
  }

  List<String> _csv(dynamic value, {List<String> fallback = const <String>[]}) {
    if (value == null) {
      return fallback;
    }
    return value
        .toString()
        .split(',')
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _normalizeSensorKey(String value) {
    final key = value.trim().toLowerCase();
    if (key == 'wind' || key == 'wind_sensor') {
      return 'wind';
    }
    return key == 'solar' ? 'uv' : key;
  }

  String _normalizeOption(String value) {
    var normalized = value.trim().toLowerCase();
    for (final separator in <String>['-', '_', '/', '&']) {
      normalized = normalized.replaceAll(separator, ' ');
    }
    return normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');
  }

  Map<String, dynamic> _jsonObject(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value == null) {
      return const <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(value.toString());
      return decoded is Map<String, dynamic>
          ? decoded
          : const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  double? _asDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }

  // ─── Realtime support ──────────────────────────────────────────────────────

  @override
  Future<Stream<SensorReading>?> connectRealtime() async {
    if (_anonKey.trim().isEmpty) return null;

    try {
      final station = await _fetchStation();
      final client = sb.Supabase.instance.client;

      _realtimeController = StreamController<SensorReading>.broadcast();

      _realtimeChannel = client
          .channel('sensor_readings_${station.id}')
          .onPostgresChanges(
            event: sb.PostgresChangeEvent.insert,
            schema: 'public',
            table: 'sensor_readings',
            filter: sb.PostgresChangeFilter(
              type: sb.PostgresChangeFilterType.eq,
              column: 'station_id',
              value: station.id,
            ),
            callback: (payload) {
              try {
                final row = payload.newRecord;
                _realtimeController?.add(
                  _readingFromRealtimeRow(row, station),
                );
              } catch (_) {
                // Ignore malformed realtime payloads.
              }
            },
          )
          .subscribe();

      return _realtimeController!.stream;
    } catch (_) {
      return null;
    }
  }

  @override
  void disposeRealtime() {
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    _realtimeController?.close();
    _realtimeController = null;
  }

  SensorReading _readingFromRealtimeRow(
    Map<String, dynamic> row,
    _StationRef station,
  ) {
    return SensorReading(
      id: (row['id'] as num).toInt(),
      deviceId: station.deviceId,
      stationName: station.name,
      recordedAt: _parseDateTime(row['recorded_at']) ?? DateTime.now(),
      receivedAt: _parseDateTime(row['received_at']) ?? DateTime.now(),
      ws: _asDouble(row['wind_speed']),
      wdDeg: _asDouble(row['wind_direction_degrees']),
      wdDir: row['wind_direction_label'] as String?,
      moist: _asDouble(row['soil_moisture']),
      temp: _asDouble(row['soil_temperature']),
      ec: _asDouble(row['soil_ec']),
      n: _asDouble(row['soil_nitrogen']),
      p: _asDouble(row['soil_phosphorus']),
      k: _asDouble(row['soil_potassium']),
      ph: _asDouble(row['soil_ph']),
      rain: _asDouble(row['rainfall']),
      solar: _asDouble(row['solar_radiation']),
    );
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

class _StationRef {
  const _StationRef({
    required this.id,
    required this.deviceId,
    required this.name,
  });

  final int id;
  final String deviceId;
  final String? name;
}

class _CropStagePreset {
  const _CropStagePreset({
    required this.crop,
    required this.stage,
    required this.lower,
    required this.upper,
  });

  final String crop;
  final String stage;
  final double lower;
  final double upper;
}
