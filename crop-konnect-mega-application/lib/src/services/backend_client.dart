import 'dart:convert';

import 'package:http/http.dart' as http;

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

class BackendClient implements StationDataSource {
  BackendClient({
    required String baseUrl,
    required String deviceId,
    http.Client? httpClient,
  })  : _baseUrl = baseUrl.replaceAll(RegExp(r'/$'), ''),
        _deviceId = deviceId,
        _httpClient = httpClient ?? createPlatformHttpClient();

  final String _baseUrl;
  final String _deviceId;
  final http.Client _httpClient;

  @override
  AppDataMode get mode => AppDataMode.live;

  @override
  String get modeLabel => 'Live Data';

  @override
  Future<SensorReading> fetchLatestReading() async {
    final uri = Uri.parse('$_baseUrl/api/v1/stations/$_deviceId/latest');
    final response = await _getJson(uri);
    return SensorReading.fromJson(response);
  }

  @override
  Future<StationSummary> fetchSummary({int hours = 24}) async {
    final uri =
        Uri.parse('$_baseUrl/api/v1/stations/$_deviceId/summary?hours=$hours');
    final response = await _getJson(uri);
    return StationSummary.fromJson(response);
  }

  @override
  Future<MonitoringStatus> fetchMonitoringStatus() async {
    final uri =
        Uri.parse('$_baseUrl/api/v1/stations/$_deviceId/monitoring-status');
    final response = await _getJson(uri);
    return MonitoringStatus.fromJson(response);
  }

  @override
  Future<StationTrends> fetchTrends({int hours = 24}) async {
    final uri =
        Uri.parse('$_baseUrl/api/v1/stations/$_deviceId/trends?hours=$hours');
    final response = await _getJson(uri);
    return StationTrends.fromJson(response);
  }

  @override
  Future<GpsReading?> fetchLatestGpsReading() async {
    final uri = Uri.parse('$_baseUrl/api/v1/stations/$_deviceId/gps/latest');
    final response = await _getJsonOrNull(uri);
    if (response == null) {
      return null;
    }
    final reading = GpsReading.fromJson(response);
    return reading;
  }

  @override
  Future<StationSettings> fetchSettings() async {
    final uri = Uri.parse('$_baseUrl/api/v1/stations/$_deviceId/settings');
    final response = await _getJson(uri);
    return StationSettings.fromJson(response);
  }

  @override
  Future<StationSettings> patchSettings(StationSettingsPatch patch) async {
    final uri = Uri.parse('$_baseUrl/api/v1/stations/$_deviceId/settings');
    final response = await _sendJson('PATCH', uri, patch.toJson());
    return StationSettings.fromJson(response);
  }

  @override
  Future<List<IrrigationCropOption>> fetchIrrigationPresets() async {
    final uri = Uri.parse('$_baseUrl/api/v1/irrigation/presets');
    final response = await _getJson(uri);
    final items = response['items'];
    return items is List
        ? items
            .whereType<Map<String, dynamic>>()
            .map(IrrigationCropOption.fromJson)
            .toList()
        : const <IrrigationCropOption>[];
  }

  @override
  Future<IrrigationProfile> fetchIrrigationProfile() async {
    final uri =
        Uri.parse('$_baseUrl/api/v1/stations/$_deviceId/irrigation/profile');
    final response = await _getJson(uri);
    return IrrigationProfile.fromJson(response);
  }

  @override
  Future<IrrigationProfile> patchIrrigationProfile(
      IrrigationProfilePatch patch) async {
    final uri =
        Uri.parse('$_baseUrl/api/v1/stations/$_deviceId/irrigation/profile');
    final response = await _sendJson('PATCH', uri, patch.toJson());
    return IrrigationProfile.fromJson(response);
  }

  @override
  Future<IrrigationAdvisory?> fetchLatestIrrigationAdvisory() async {
    final uri = Uri.parse(
        '$_baseUrl/api/v1/stations/$_deviceId/irrigation/advisory/latest');
    final response = await _getJsonOrNull(uri);
    return response == null ? null : IrrigationAdvisory.fromJson(response);
  }

  @override
  Future<Stream<SensorReading>?> connectRealtime() async => null;

  @override
  void disposeRealtime() {}

  Future<Map<String, dynamic>?> _getJsonOrNull(Uri uri) async {
    final response =
        await _httpClient.get(uri, headers: _jsonHeaders(acceptOnly: true));
    final body = response.body;

    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Request failed with status ${response.statusCode}: $body ($uri)',
      );
    }

    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response =
        await _httpClient.get(uri, headers: _jsonHeaders(acceptOnly: true));
    final body = response.body;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Request failed with status ${response.statusCode}: $body ($uri)',
      );
    }

    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _sendJson(
      String method, Uri uri, Map<String, dynamic> payload) async {
    final response = switch (method.toUpperCase()) {
      'PATCH' => await _httpClient.patch(
          uri,
          headers: _jsonHeaders(),
          body: jsonEncode(payload),
        ),
      'POST' => await _httpClient.post(
          uri,
          headers: _jsonHeaders(),
          body: jsonEncode(payload),
        ),
      _ => throw UnsupportedError('Unsupported method: $method'),
    };
    final body = response.body;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Request failed with status ${response.statusCode}: $body ($uri)',
      );
    }

    return jsonDecode(body) as Map<String, dynamic>;
  }

  Map<String, String> _jsonHeaders({bool acceptOnly = false}) {
    return <String, String>{
      'Accept': 'application/json',
      if (!acceptOnly) 'Content-Type': 'application/json',
    };
  }
}
