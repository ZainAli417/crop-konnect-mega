import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/weather_fallback.dart';
import '../models/weather_forecast.dart';
import 'platform_http_client.dart';

/// Pulls current + last-24 h wind, rain and UV/solar for a fixed field
/// location.
///
/// Used only as a stand-in while the station itself is dark; the values are
/// merged into the normal reading objects by the dashboard controller, so
/// nothing downstream has to know where a number came from.
class OpenMeteoWeatherService {
  OpenMeteoWeatherService({http.Client? httpClient})
      : _httpClient = httpClient ?? createPlatformHttpClient();

  static const String _host = 'api.open-meteo.com';
  static const String _path = '/v1/forecast';

  final http.Client _httpClient;

  Future<WeatherFallback> fetch({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https(_host, _path, <String, String>{
      'latitude': latitude.toStringAsFixed(4),
      'longitude': longitude.toStringAsFixed(4),
      'current': 'temperature_2m,relative_humidity_2m,precipitation,'
          'wind_speed_10m,wind_direction_10m,shortwave_radiation,uv_index',
      'hourly': 'precipitation,wind_speed_10m,wind_direction_10m,'
          'shortwave_radiation,uv_index',
      'wind_speed_unit': 'ms',
      'past_days': '1',
      'forecast_days': '1',
      'timezone': 'UTC',
    });

    final response = await _httpClient.get(
      uri,
      headers: const <String, String>{'Accept': 'application/json'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Weather request failed with status ${response.statusCode}: '
        '${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final current = body['current'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final now = DateTime.now();

    final windDeg = _asDouble(current['wind_direction_10m']);

    return WeatherFallback(
      fetchedAt: now,
      observedAt: _parseUtc(current['time']) ?? now,
      latitude: latitude,
      longitude: longitude,
      windSpeedMs: _asDouble(current['wind_speed_10m']),
      windDirectionDeg: windDeg,
      windDirectionLabel: compassLabel(windDeg),
      rainMm: _asDouble(current['precipitation']),
      solarWm2: _asDouble(current['shortwave_radiation']),
      uvIndex: _asDouble(current['uv_index']),
      airTempC: _asDouble(current['temperature_2m']),
      humidityPct: _asDouble(current['relative_humidity_2m']),
      history: _historyFrom(body['hourly'], now),
    );
  }

  /// The 14-day outlook for the field.
  ///
  /// Daily aggregates are requested with `timezone=auto` so each bucket lines
  /// up with a local calendar day rather than a UTC one.
  Future<WeatherForecast> fetchForecast({
    required double latitude,
    required double longitude,
    int days = 14,
  }) async {
    final uri = Uri.https(_host, _path, <String, String>{
      'latitude': latitude.toStringAsFixed(4),
      'longitude': longitude.toStringAsFixed(4),
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,'
          'precipitation_sum,precipitation_probability_max,'
          'wind_speed_10m_max,wind_direction_10m_dominant,uv_index_max,'
          'sunrise,sunset',
      'wind_speed_unit': 'ms',
      'forecast_days': '$days',
      'timezone': 'auto',
    });

    final response = await _httpClient.get(
      uri,
      headers: const <String, String>{'Accept': 'application/json'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Forecast request failed with status ${response.statusCode}: '
        '${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final daily = body['daily'];
    if (daily is! Map<String, dynamic>) {
      throw StateError('Forecast response carried no daily block.');
    }

    final times = daily['time'] as List<dynamic>? ?? const <dynamic>[];
    if (times.isEmpty) {
      throw StateError('Forecast response carried no days.');
    }

    List<dynamic> column(String key) =>
        daily[key] as List<dynamic>? ?? const <dynamic>[];

    final codes = column('weather_code');
    final tempMax = column('temperature_2m_max');
    final tempMin = column('temperature_2m_min');
    final precip = column('precipitation_sum');
    final precipChance = column('precipitation_probability_max');
    final windMax = column('wind_speed_10m_max');
    final windDir = column('wind_direction_10m_dominant');
    final uvMax = column('uv_index_max');
    final sunrise = column('sunrise');
    final sunset = column('sunset');

    double? at(List<dynamic> values, int i) =>
        i < values.length ? _asDouble(values[i]) : null;
    DateTime? timeAt(List<dynamic> values, int i) =>
        i < values.length ? _parseLocal(values[i]) : null;

    final result = <ForecastDay>[];
    for (var i = 0; i < times.length; i++) {
      final date = _parseLocal(times[i]);
      if (date == null) continue;
      result.add(
        ForecastDay(
          date: DateTime(date.year, date.month, date.day),
          weatherCode: at(codes, i)?.round(),
          tempMaxC: at(tempMax, i),
          tempMinC: at(tempMin, i),
          precipitationMm: at(precip, i),
          precipitationChance: at(precipChance, i),
          windMaxMs: at(windMax, i),
          windDirectionDeg: at(windDir, i),
          uvIndexMax: at(uvMax, i),
          sunrise: timeAt(sunrise, i),
          sunset: timeAt(sunset, i),
        ),
      );
    }

    return WeatherForecast(
      fetchedAt: DateTime.now(),
      latitude: latitude,
      longitude: longitude,
      days: result,
    );
  }

  /// The trailing 24 h of hourly values, oldest-first. Hours in the future
  /// (the forecast half of the window) are dropped.
  static List<WeatherSample> _historyFrom(dynamic raw, DateTime now) {
    if (raw is! Map<String, dynamic>) return const <WeatherSample>[];

    final times = (raw['time'] as List<dynamic>? ?? const <dynamic>[]);
    if (times.isEmpty) return const <WeatherSample>[];

    List<dynamic> column(String key) =>
        raw[key] as List<dynamic>? ?? const <dynamic>[];

    final wind = column('wind_speed_10m');
    final windDir = column('wind_direction_10m');
    final rain = column('precipitation');
    final solar = column('shortwave_radiation');
    final uv = column('uv_index');

    double? at(List<dynamic> values, int i) =>
        i < values.length ? _asDouble(values[i]) : null;

    final cutoff = now.subtract(const Duration(hours: 24));
    final samples = <WeatherSample>[];
    for (var i = 0; i < times.length; i++) {
      final timestamp = _parseUtc(times[i]);
      if (timestamp == null) continue;
      if (timestamp.isBefore(cutoff) || timestamp.isAfter(now)) continue;
      samples.add(
        WeatherSample(
          timestamp: timestamp,
          windSpeedMs: at(wind, i),
          windDirectionDeg: at(windDir, i),
          rainMm: at(rain, i),
          solarWm2: at(solar, i),
          uvIndex: at(uv, i),
        ),
      );
    }
    return samples;
  }

  /// 16-point compass label, matching the labels the station itself reports.
  static String? compassLabel(double? degrees) {
    if (degrees == null) return null;
    const points = <String>[
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
    ];
    var normalized = degrees % 360;
    if (normalized < 0) normalized += 360;
    return points[(normalized / 22.5).round() % 16];
  }

  /// Under `timezone=auto` the API has already shifted the value into the
  /// field's own zone, so it is parsed as-is rather than converted.
  static DateTime? _parseLocal(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  /// Timestamps come back without a zone designator under `timezone=UTC`.
  static DateTime? _parseUtc(dynamic value) {
    if (value == null) return null;
    final text = value.toString();
    final parsed = DateTime.tryParse(text.endsWith('Z') ? text : '${text}Z');
    return parsed?.toLocal();
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
