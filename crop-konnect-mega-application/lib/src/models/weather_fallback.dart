import '../services/station_status_builder.dart';
import 'monitoring_status.dart';
import 'sensor_reading.dart';
import 'station_settings.dart';
import 'station_trends.dart';

/// A point in the fallback weather history.
class WeatherSample {
  const WeatherSample({
    required this.timestamp,
    this.windSpeedMs,
    this.windDirectionDeg,
    this.rainMm,
    this.solarWm2,
    this.uvIndex,
  });

  final DateTime timestamp;
  final double? windSpeedMs;
  final double? windDirectionDeg;
  final double? rainMm;
  final double? solarWm2;
  final double? uvIndex;
}

/// Weather values used in place of the station's own wind / rain / UV block.
///
/// The station is solar powered and goes dark for long stretches, so once its
/// readings age past [WeatherFallback.stalenessWindow] the dashboard, the
/// graphs and the DSS all need *some* current weather to work from. This holds
/// that substitute set plus the matching 24 h history, and knows how to fold
/// itself into a [SensorReading], a [StationTrends] and a [MonitoringStatus] so
/// the rest of the app keeps reading from exactly the same objects it always
/// has.
///
/// Soil values are never touched — only wind, rain and UV/solar, plus the air
/// temperature and humidity the station has no sensor for at all.
class WeatherFallback {
  const WeatherFallback({
    required this.fetchedAt,
    required this.observedAt,
    required this.latitude,
    required this.longitude,
    this.windSpeedMs,
    this.windDirectionDeg,
    this.windDirectionLabel,
    this.rainMm,
    this.solarWm2,
    this.uvIndex,
    this.airTempC,
    this.humidityPct,
    this.history = const <WeatherSample>[],
  });

  /// Station readings older than this are considered dark, and the fallback
  /// takes over.
  static const Duration stalenessWindow = Duration(hours: 24);

  /// How long a fetched set stays good before it is refreshed.
  static const Duration refreshInterval = Duration(hours: 3);

  final DateTime fetchedAt;
  final DateTime observedAt;
  final double latitude;
  final double longitude;
  final double? windSpeedMs;
  final double? windDirectionDeg;
  final String? windDirectionLabel;
  final double? rainMm;
  final double? solarWm2;
  final double? uvIndex;
  final double? airTempC;
  final double? humidityPct;
  final List<WeatherSample> history;

  bool isExpiredAt(DateTime now) =>
      now.difference(fetchedAt) >= refreshInterval;

  /// Replace [reading]'s weather block, keeping every soil value as-is.
  ///
  /// When the station has never reported at all, [deviceId] and [stationName]
  /// seed a reading that carries the weather and leaves soil null.
  SensorReading applyTo(
    SensorReading? reading, {
    required String deviceId,
    String? stationName,
  }) {
    if (reading == null) {
      return SensorReading(
        id: -1,
        deviceId: deviceId,
        stationName: stationName,
        recordedAt: observedAt,
        receivedAt: observedAt,
        ws: windSpeedMs,
        wdDeg: windDirectionDeg,
        wdDir: windDirectionLabel,
        moist: null,
        temp: null,
        ec: null,
        n: null,
        p: null,
        k: null,
        ph: null,
        rain: rainMm,
        solar: solarWm2,
        airTempC: airTempC,
        humidityPct: humidityPct,
        uvIndex: uvIndex,
      );
    }

    return reading.copyWith(
      recordedAt: observedAt,
      receivedAt: observedAt,
      ws: windSpeedMs,
      wdDeg: windDirectionDeg,
      wdDir: windDirectionLabel,
      rain: rainMm,
      solar: solarWm2,
      airTempC: airTempC,
      humidityPct: humidityPct,
      uvIndex: uvIndex,
    );
  }

  /// Swap the wind / rain / UV series for the fallback history, leaving every
  /// soil series untouched. Series with no history are left alone.
  StationTrends applyToTrends(StationTrends? trends, {required String deviceId}) {
    final series = Map<String, List<TrendPoint>>.from(
      trends?.series ?? const <String, List<TrendPoint>>{},
    );

    void overlay(String key, double? Function(WeatherSample) pick) {
      final points = <TrendPoint>[];
      for (final sample in history) {
        final value = pick(sample);
        if (value == null) continue;
        points.add(TrendPoint(timestamp: sample.timestamp, value: value));
      }
      if (points.isEmpty) return;
      series[key] = points;
    }

    overlay('ws', (s) => s.windSpeedMs);
    overlay('rain', (s) => s.rainMm);
    overlay('uv', (s) => s.solarWm2);

    return StationTrends(
      deviceId: trends?.deviceId ?? deviceId,
      hours: trends?.hours ?? 24,
      series: series,
    );
  }

  /// Rebuild the monitoring status from the substituted reading.
  ///
  /// The substitute set stands in for the logger completely, so conditions,
  /// sensor health, alerts and the overall roll-up are all re-derived from the
  /// merged reading with [StationStatusBuilder] — the very same rules the cloud
  /// source applies to a live row. Because that reading is stamped with the
  /// observation time, sensors read online and fresh, and the stale-data alert
  /// does not fire.
  ///
  /// [settings] decides which sensor groups are switched on; without it the
  /// flags carry over from [status], and failing that every group is treated as
  /// enabled so the substituted weather is actually reported.
  MonitoringStatus applyToMonitoring(
    MonitoringStatus? status, {
    required SensorReading merged,
    StationSettings? settings,
  }) {
    final Map<String, bool> enabled;
    if (settings != null) {
      enabled = StationStatusBuilder.enabledFromSettings(settings);
    } else if (status != null) {
      enabled = StationStatusBuilder.enabledFromHealth(status.sensorHealth);
    } else {
      enabled = <String, bool>{
        for (final key in StationStatusBuilder.sensorKeys) key: true,
      };
    }

    return const StationStatusBuilder().build(reading: merged, enabled: enabled);
  }
}
