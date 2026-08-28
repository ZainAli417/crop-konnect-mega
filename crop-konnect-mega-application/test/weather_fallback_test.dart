import 'dart:convert';

import 'package:ess_sensor_ck/src/models/sensor_reading.dart';
import 'package:ess_sensor_ck/src/models/station_trends.dart';
import 'package:ess_sensor_ck/src/models/weather_fallback.dart';
import 'package:ess_sensor_ck/src/services/open_meteo_weather_service.dart';
import 'package:ess_sensor_ck/src/services/station_status_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Hourly timestamps are built around "now" so the 24 h filter is exercised
/// the same way it will be at runtime.
String _utcHour(Duration offset) {
  final t = DateTime.now().toUtc().add(offset);
  final iso = DateTime.utc(t.year, t.month, t.day, t.hour).toIso8601String();
  return iso.substring(0, 16); // "YYYY-MM-DDTHH:mm", no zone — as the API sends
}

String _body() => jsonEncode(<String, dynamic>{
      'current': <String, dynamic>{
        'time': _utcHour(Duration.zero),
        'temperature_2m': 36.6,
        'relative_humidity_2m': 44,
        'precipitation': 0.0,
        'wind_speed_10m': 3.97,
        'wind_direction_10m': 211,
        'shortwave_radiation': 794.0,
        'uv_index': 7.15,
      },
      'hourly': <String, dynamic>{
        'time': <String>[
          _utcHour(const Duration(hours: -30)), // outside the window
          _utcHour(const Duration(hours: -2)),
          _utcHour(const Duration(hours: -1)),
          _utcHour(const Duration(hours: 6)), // forecast, not history
        ],
        'precipitation': <double>[0, 0.2, 0.4, 1.0],
        'wind_speed_10m': <double>[1, 2.29, 2.53, 9.9],
        'wind_direction_10m': <double>[10, 20, 30, 40],
        'shortwave_radiation': <double>[0, 65, 120, 500],
        'uv_index': <double>[0, 0.4, 1.2, 6],
      },
    });

SensorReading _stationReading(DateTime recordedAt) => SensorReading(
      id: 7,
      deviceId: 'RPAWTEX',
      stationName: 'Field Station 1',
      recordedAt: recordedAt,
      receivedAt: recordedAt,
      ws: 0.4,
      wdDeg: 12,
      wdDir: 'N',
      moist: 23.5,
      temp: 27.1,
      ec: 910,
      n: 44,
      p: 18,
      k: 61,
      ph: 7.2,
      rain: 0,
      solar: 3,
    );

void main() {
  group('OpenMeteoWeatherService', () {
    test('parses the current block and trims history to the last 24 h',
        () async {
      late Uri requested;
      final service = OpenMeteoWeatherService(
        httpClient: MockClient((request) async {
          requested = request.url;
          return http.Response(_body(), 200);
        }),
      );

      final result =
          await service.fetch(latitude: 30.1575, longitude: 71.5249);

      expect(requested.queryParameters['wind_speed_unit'], 'ms');
      expect(requested.queryParameters['timezone'], 'UTC');

      expect(result.windSpeedMs, 3.97);
      expect(result.windDirectionDeg, 211);
      expect(result.windDirectionLabel, 'SSW');
      expect(result.rainMm, 0.0);
      expect(result.solarWm2, 794.0);
      expect(result.uvIndex, 7.15);
      expect(result.airTempC, 36.6);
      expect(result.humidityPct, 44);

      // The 30-h-old row and the forecast row are both dropped.
      expect(result.history.length, 2);
      expect(result.history.first.windSpeedMs, 2.29);
      expect(result.history.last.solarWm2, 120);
    });

    test('compass labels wrap correctly', () {
      expect(OpenMeteoWeatherService.compassLabel(0), 'N');
      expect(OpenMeteoWeatherService.compassLabel(359), 'N');
      expect(OpenMeteoWeatherService.compassLabel(90), 'E');
      expect(OpenMeteoWeatherService.compassLabel(211), 'SSW');
      expect(OpenMeteoWeatherService.compassLabel(null), isNull);
    });
  });

  group('WeatherFallback overlay', () {
    final fallback = WeatherFallback(
      fetchedAt: DateTime.now(),
      observedAt: DateTime.now(),
      latitude: 30.1575,
      longitude: 71.5249,
      windSpeedMs: 3.97,
      windDirectionDeg: 211,
      windDirectionLabel: 'SSW',
      rainMm: 0.0,
      solarWm2: 794.0,
      uvIndex: 7.15,
      airTempC: 36.6,
      humidityPct: 44,
      history: <WeatherSample>[
        WeatherSample(
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
          windSpeedMs: 2.53,
          rainMm: 0.4,
          solarWm2: 120,
          uvIndex: 1.2,
        ),
      ],
    );

    test('replaces weather and leaves every soil value alone', () {
      final stale = _stationReading(
        DateTime.now().subtract(const Duration(days: 4)),
      );

      final merged = fallback.applyTo(stale, deviceId: 'RPAWTEX');

      // Weather comes from the substitute set.
      expect(merged.ws, 3.97);
      expect(merged.wdDeg, 211);
      expect(merged.wdDir, 'SSW');
      expect(merged.solar, 794.0);
      expect(merged.uvIndex, 7.15);
      expect(merged.airTempC, 36.6);
      expect(merged.humidityPct, 44);

      // Soil is untouched.
      expect(merged.moist, 23.5);
      expect(merged.temp, 27.1);
      expect(merged.ec, 910);
      expect(merged.n, 44);
      expect(merged.p, 18);
      expect(merged.k, 61);
      expect(merged.ph, 7.2);
    });

    test('synthesises a reading when the station has never reported', () {
      final merged = fallback.applyTo(null, deviceId: 'RPAWTEX');
      expect(merged.deviceId, 'RPAWTEX');
      expect(merged.ws, 3.97);
      expect(merged.moist, isNull);
    });

    test('overlays only the weather series in the graphs', () {
      final soilPoints = <TrendPoint>[
        TrendPoint(timestamp: DateTime.now(), value: 21),
      ];
      final stationTrends = StationTrends(
        deviceId: 'RPAWTEX',
        hours: 24,
        series: <String, List<TrendPoint>>{
          'moist': soilPoints,
          'ws': const <TrendPoint>[],
          'rain': const <TrendPoint>[],
          'uv': const <TrendPoint>[],
        },
      );

      final merged =
          fallback.applyToTrends(stationTrends, deviceId: 'RPAWTEX');

      expect(merged.series['moist'], same(soilPoints));
      expect(merged.series['ws']!.single.value, 2.53);
      expect(merged.series['rain']!.single.value, 0.4);
      expect(merged.series['uv']!.single.value, 120);
    });

    test('sensor health binds to the substituted reading, not the dead logger',
        () {
      final staleReading = _stationReading(
        DateTime.now().subtract(const Duration(days: 4)),
      );

      // What the cloud reported while the station was dark: everything stale,
      // with a data-delay alert.
      final darkStatus = const StationStatusBuilder().build(
        reading: staleReading,
        enabled: const <String, bool>{
          'wind': true,
          'soil': true,
          'rain': true,
          'uv': true,
        },
      );
      expect(darkStatus.sensorHealth['wind']!.freshness, 'stale');
      expect(darkStatus.alerts.map((a) => a.type), contains('stale_data'));
      expect(darkStatus.overallStatus, 'attention');

      final merged = fallback.applyTo(staleReading, deviceId: 'RPAWTEX');
      final rebuilt = fallback.applyToMonitoring(darkStatus, merged: merged);

      // The substitute set is treated as the logger's own, so every enabled
      // sensor reads online and the delay alert is gone.
      for (final key in StationStatusBuilder.sensorKeys) {
        expect(rebuilt.sensorHealth[key]!.status, 'online', reason: key);
        expect(rebuilt.sensorHealth[key]!.freshness, 'fresh', reason: key);
      }
      expect(rebuilt.alerts.map((a) => a.type), isNot(contains('stale_data')));
      expect(rebuilt.lastUpdated, merged.recordedAt);

      // Conditions come from the substituted values.
      expect(rebuilt.conditions['wind'], 'calm'); // 3.97 m/s
      expect(rebuilt.conditions['uv'], 'high'); // 794 W/m2
      expect(rebuilt.conditions['rain'], 'not_detected');
    });

    test('a disabled sensor stays disabled after substitution', () {
      final staleReading = _stationReading(
        DateTime.now().subtract(const Duration(days: 4)),
      );
      final darkStatus = const StationStatusBuilder().build(
        reading: staleReading,
        enabled: const <String, bool>{
          'wind': true,
          'soil': true,
          'rain': false,
          'uv': true,
        },
      );

      final rebuilt = fallback.applyToMonitoring(
        darkStatus,
        merged: fallback.applyTo(staleReading, deviceId: 'RPAWTEX'),
      );

      expect(rebuilt.sensorHealth['rain']!.status, 'disabled');
      expect(rebuilt.sensorHealth['wind']!.status, 'online');
    });

    test('substituted wind still raises the high-wind alert', () {
      final gusty = WeatherFallback(
        fetchedAt: DateTime.now(),
        observedAt: DateTime.now(),
        latitude: 0,
        longitude: 0,
        windSpeedMs: 14.2,
        rainMm: 0,
        solarWm2: 100,
      );
      final merged = gusty.applyTo(null, deviceId: 'RPAWTEX');
      final status = gusty.applyToMonitoring(null, merged: merged);

      expect(status.conditions['wind'], 'high');
      expect(status.alerts.map((a) => a.type), contains('high_wind'));
      expect(status.overallStatus, 'attention');
    });

    test('expires after the refresh interval', () {
      final now = DateTime.now();
      final fresh = WeatherFallback(
        fetchedAt: now.subtract(const Duration(hours: 2)),
        observedAt: now,
        latitude: 0,
        longitude: 0,
      );
      final old = WeatherFallback(
        fetchedAt: now.subtract(const Duration(hours: 3, minutes: 1)),
        observedAt: now,
        latitude: 0,
        longitude: 0,
      );

      expect(fresh.isExpiredAt(now), isFalse);
      expect(old.isExpiredAt(now), isTrue);
    });
  });
}
