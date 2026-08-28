import 'dart:convert';

import 'package:ess_sensor_ck/src/models/weather_forecast.dart';
import 'package:ess_sensor_ck/src/services/open_meteo_weather_service.dart';
import 'package:ess_sensor_ck/src/widgets/weather_forecast_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _day(int offset) {
  final d = DateTime.now().add(Duration(days: offset));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Mirrors a real Open-Meteo daily block, 14 days wide.
String _body() {
  const codes = <int>[1, 0, 0, 3, 61, 80, 95, 2, 0, 45, 71, 3, 1, 0];
  return jsonEncode(<String, dynamic>{
    'daily': <String, dynamic>{
      'time': <String>[for (var i = 0; i < 14; i++) _day(i)],
      'weather_code': codes,
      'temperature_2m_max': <double>[
        38.8, 37.9, 38.2, 36.0, 31.4, 30.2, 29.8,
        33.1, 35.5, 34.2, 33.8, 36.6, 37.2, 38.0,
      ],
      'temperature_2m_min': <double>[
        31.2, 29.7, 29.7, 28.4, 25.1, 24.8, 24.2,
        26.0, 27.4, 26.9, 26.2, 28.1, 29.0, 29.6,
      ],
      'precipitation_sum': <double>[
        0, 0, 0, 0.4, 12.6, 8.2, 21.0, 0.2, 0, 0, 0, 0, 0, 0,
      ],
      'precipitation_probability_max': <int>[
        0, 0, 0, 20, 85, 70, 95, 15, 0, 0, 5, 0, 0, 0,
      ],
      'wind_speed_10m_max': <double>[
        4.98, 4.2, 4.24, 5.1, 7.8, 6.4, 11.2,
        5.0, 4.4, 3.9, 4.1, 4.6, 4.8, 5.2,
      ],
      'wind_direction_10m_dominant': <int>[
        200, 183, 183, 190, 210, 205, 220, 195, 188, 180, 185, 192, 198, 201,
      ],
      'uv_index_max': <double>[
        7.6, 7.55, 7.55, 6.8, 4.2, 5.0, 3.8,
        6.9, 7.2, 6.5, 6.1, 7.0, 7.3, 7.5,
      ],
      'sunrise': <String>[for (var i = 0; i < 14; i++) '${_day(i)}T05:48'],
      'sunset': <String>[for (var i = 0; i < 14; i++) '${_day(i)}T18:43'],
    },
  });
}

void main() {
  group('fetchForecast', () {
    test('parses 14 days with the fields the sheet renders', () async {
      late Uri requested;
      final service = OpenMeteoWeatherService(
        httpClient: MockClient((request) async {
          requested = request.url;
          return http.Response(_body(), 200);
        }),
      );

      final forecast =
          await service.fetchForecast(latitude: 30.1575, longitude: 71.5249);

      expect(requested.queryParameters['forecast_days'], '14');
      // Daily buckets must align to local calendar days, not UTC ones.
      expect(requested.queryParameters['timezone'], 'auto');
      expect(requested.queryParameters['wind_speed_unit'], 'ms');

      expect(forecast.days.length, 14);

      final today = forecast.today!;
      expect(today.isToday, isTrue);
      expect(today.tempMaxC, 38.8);
      expect(today.tempMinC, 31.2);
      expect(today.uvIndexMax, 7.6);
      expect(today.windMaxMs, 4.98);
      expect(today.sunrise!.hour, 5);
      expect(today.sunset!.hour, 18);
    });

    test('rolls up the outlook for the summary strip', () async {
      final service = OpenMeteoWeatherService(
        httpClient: MockClient((_) async => http.Response(_body(), 200)),
      );

      final forecast =
          await service.fetchForecast(latitude: 0, longitude: 0);

      expect(forecast.totalRainMm, closeTo(42.4, 0.001));
      expect(forecast.warmestC, 38.8);
      expect(forecast.coolestC, 24.2);

      // Day index 3 has only 0.4 mm at 20 % — the first day that actually
      // matters is index 4.
      expect(forecast.nextWetDay!.date.day,
          DateTime.now().add(const Duration(days: 4)).day);
    });

    test('maps WMO codes onto the glyph families', () async {
      final service = OpenMeteoWeatherService(
        httpClient: MockClient((_) async => http.Response(_body(), 200)),
      );
      final days = (await service.fetchForecast(latitude: 0, longitude: 0)).days;

      expect(days[0].kind, WeatherKind.partlyCloudy); // 1
      expect(days[1].kind, WeatherKind.clear); // 0
      expect(days[3].kind, WeatherKind.cloudy); // 3
      expect(days[4].kind, WeatherKind.rain); // 61
      expect(days[5].kind, WeatherKind.showers); // 80
      expect(days[6].kind, WeatherKind.thunderstorm); // 95
      expect(days[9].kind, WeatherKind.fog); // 45
      expect(days[10].kind, WeatherKind.snow); // 71

      expect(days[6].kind.isWet, isTrue);
      expect(days[1].kind.isWet, isFalse);
    });

    test('throws rather than returning an empty outlook', () async {
      final service = OpenMeteoWeatherService(
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(<String, dynamic>{}), 200),
        ),
      );

      expect(
        () => service.fetchForecast(latitude: 0, longitude: 0),
        throwsA(isA<StateError>()),
      );
    });

    test('surfaces a non-2xx response as an error', () async {
      final service = OpenMeteoWeatherService(
        httpClient: MockClient((_) async => http.Response('rate limited', 429)),
      );

      expect(
        () => service.fetchForecast(latitude: 0, longitude: 0),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('cooldown label', () {
    test('reads down through hours, minutes and seconds', () {
      expect(formatCooldown(const Duration(hours: 5, minutes: 42)), '5h 42m');
      expect(formatCooldown(const Duration(hours: 1)), '1h 0m');
      expect(formatCooldown(const Duration(minutes: 58)), '58m');
      expect(formatCooldown(const Duration(seconds: 44)), '44s');
      expect(formatCooldown(Duration.zero), '0s');
    });
  });
}
