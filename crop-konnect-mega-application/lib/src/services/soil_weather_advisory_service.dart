import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/sensor_reading.dart';
import '../models/soil_sample.dart';
import '../models/soil_weather_advisory.dart';
import 'platform_http_client.dart';

/// Calls the remote soil-weather advisory (DSS) service.
///
/// Given the crop, sowing date, observation date and the field's latest soil +
/// weather readings, the backend returns a farmer-facing advisory. This
/// replaces the on-device DSS engine for the advisory tab.
class SoilWeatherAdvisoryService {
  SoilWeatherAdvisoryService({
    String? baseUrl,
    http.Client? httpClient,
  })  : _baseUrl = (baseUrl ?? AppConfig.advisoryApiBaseUrl)
            .replaceAll(RegExp(r'/$'), ''),
        _httpClient = httpClient ?? createPlatformHttpClient();

  final String _baseUrl;
  final http.Client _httpClient;

  Future<SoilWeatherAdvisory> fetchAdvisory({
    required String cropName,
    required DateTime sowingDate,
    required DateTime observationDate,
    required String language,
    SensorReading? reading,
    SoilSample? soilSample,
  }) async {
    final uri = Uri.parse('$_baseUrl/advisory/api/advisory/soil-weather');

    final payload = <String, dynamic>{
      'crop_name': cropName,
      'sowing_date': _formatDate(sowingDate),
      'observation_date': _formatDate(observationDate),
      'language': language,
      'soil_sensor': _soilSensorPayload(reading, soilSample),
      'weather_station': _weatherStationPayload(reading),
    };

    final response = await _httpClient.post(
      uri,
      headers: const <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    final body = response.body;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Advisory request failed with status ${response.statusCode}: '
        '$body ($uri)',
      );
    }

    return SoilWeatherAdvisory.fromJson(
      jsonDecode(body) as Map<String, dynamic>,
    );
  }

  /// Builds the soil sensor block. Any reading the station did not send is
  /// sent as 0 so the payload is always complete.
  ///
  /// When [sample] is given (the user chose to run the DSS on a recorded soil
  /// sample) its values take the place of the live sensor's — the block keeps
  /// the exact same shape, and no other part of the payload changes.
  Map<String, dynamic> _soilSensorPayload(SensorReading? r, SoilSample? sample) {
    if (sample != null) {
      return <String, dynamic>{
        'n': sample.nitrogen,
        'p': sample.phosphorus,
        'k': sample.potassium,
        'ph': sample.ph,
        'ec': sample.ec,
        'soil_temperature': sample.temperature,
        'soil_moisture': sample.moisture,
        'calibration_status': 'verified',
      };
    }
    return <String, dynamic>{
      'n': r?.n ?? 0,
      'p': r?.p ?? 0,
      'k': r?.k ?? 0,
      'ph': r?.ph ?? 0,
      'ec': r?.ec ?? 0,
      'soil_temperature': r?.temp ?? 0,
      'soil_moisture': r?.moist ?? 0,
      'calibration_status': 'verified',
    };
  }

  /// Builds the weather block. Wind is converted from m/s to km/h; any reading
  /// the station does not report (air temperature, humidity, UV) is sent as 0.
  Map<String, dynamic> _weatherStationPayload(SensorReading? r) {
    final ws = r?.ws;
    return <String, dynamic>{
      'temperature': 0,
      'humidity': 0,
      'wind_speed_kmh':
          ws == null ? 0 : double.parse((ws * 3.6).toStringAsFixed(1)),
      'uv': 0,
      'rain': r?.rain ?? 0,
    };
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
