import 'package:ess_sensor_ck/src/models/weather_forecast.dart';
import 'package:ess_sensor_ck/src/widgets/weather_forecast_sheet.dart';
import 'package:ess_sensor_ck/src/widgets/weather_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WeatherForecast _forecast({List<int>? codes, bool dry = false}) {
  final today = DateTime.now();
  final resolved = codes ??
      const <int>[1, 0, 0, 3, 61, 80, 95, 2, 0, 45, 71, 3, 1, 0];
  return WeatherForecast(
    fetchedAt: today,
    latitude: 30.1575,
    longitude: 71.5249,
    days: <ForecastDay>[
      for (var i = 0; i < resolved.length; i++)
        ForecastDay(
          date: DateTime(today.year, today.month, today.day)
              .add(Duration(days: i)),
          weatherCode: resolved[i],
          tempMaxC: 30 + (i % 5).toDouble(),
          tempMinC: 20 + (i % 4).toDouble(),
          precipitationMm: !dry && i == 4 ? 12.6 : 0,
          precipitationChance: !dry && i == 4 ? 85 : 0,
          windMaxMs: 4 + (i % 3).toDouble(),
          windDirectionDeg: 200,
          uvIndexMax: 7.6,
          sunrise: DateTime(today.year, today.month, today.day, 5, 48),
          sunset: DateTime(today.year, today.month, today.day, 18, 43),
        ),
    ],
  );
}

void _useTallPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _openSheet(WidgetTester tester, WeatherForecast forecast) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showWeatherForecastSheet(context, forecast),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // Let the sheet settle and the staggered reveals fire.
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('the sheet renders the hero, summary and all 14 days',
      (tester) async {
    _useTallPhoneViewport(tester);

    await _openSheet(tester, _forecast());

    expect(find.text('14-day forecast'), findsOneWidget);
    expect(find.text('Trend'), findsOneWidget);
    expect(find.text('Daily outlook'), findsOneWidget);
    expect(find.text('Conditions'), findsOneWidget);
    expect(find.text('14 days'), findsOneWidget);
    expect(find.text('Today'), findsWidgets);

    // One glyph in the now card, one per day row.
    expect(find.byType(WeatherGlyph), findsNWidgets(15));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every weather family paints without error', (tester) async {
    _useTallPhoneViewport(tester);

    // One day per glyph family, so each branch of the painter runs.
    await _openSheet(
      tester,
      _forecast(codes: const <int>[0, 1, 3, 45, 51, 61, 80, 71, 95]),
    );

    // Advance through a full animation loop to exercise the time-varying
    // paths (sun rays, drop wrap-around, the bolt flash).
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the trend control swaps between all four metrics',
      (tester) async {
    _useTallPhoneViewport(tester);

    await _openSheet(tester, _forecast());

    // Temperature is the landing metric and is the only one with a legend.
    expect(find.text('°C'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);

    for (final segment in <String>['Rain', 'Wind', 'UV']) {
      await tester.tap(find.byKey(ValueKey<String>('trend-segment-$segment')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: segment);
    }

    // UV is showing now, so the high/low legend is gone.
    expect(find.text('index'), findsOneWidget);
    expect(find.text('High'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('trend-segment-Temp')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('High'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rainless window falls back to an empty rain chart',
      (tester) async {
    _useTallPhoneViewport(tester);

    await _openSheet(
      tester,
      _forecast(codes: const <int>[0, 0, 0, 0, 0, 0, 0], dry: true),
    );

    await tester.tap(find.byKey(const ValueKey<String>('trend-segment-Rain')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('No rain expected in this window'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dry outlook shows the no-rain callout', (tester) async {
    _useTallPhoneViewport(tester);

    await _openSheet(
      tester,
      _forecast(codes: const <int>[0, 0, 0, 0, 0, 0, 0], dry: true),
    );

    expect(
      find.textContaining('No meaningful rain'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
