import 'dart:math' as math;

import '../config/app_config.dart';
import '../models/irrigation.dart';
import '../models/monitoring_status.dart';
import '../models/sensor_reading.dart';
import '../models/station_settings.dart';
import '../models/station_summary.dart';
import '../models/station_trends.dart';
import '../models/gps_reading.dart';
import 'station_data_source.dart';

class MockStationDataSource implements StationDataSource {
  MockStationDataSource({
    required this.deviceId,
    required this.stationName,
  });

  final String deviceId;
  final String stationName;

  int _tick = 0;
  final Map<String, bool> _sensorEnabled = <String, bool>{
    'wind_speed': false,
    'wind_direction': false,
    'soil': false,
    'rain': false,
    'uv': false,
  };

  int _pollIntervalSeconds = 12;
  int _interReadDelayMs = 700;
  final Map<String, int> _sensorIntervals = <String, int>{
    'wind': kDefaultSensorIntervalSeconds,
    'soil': kDefaultSensorIntervalSeconds,
    'rain': kDefaultSensorIntervalSeconds,
    'uv': kDefaultSensorIntervalSeconds,
  };
  List<String> _sensorReadOrder = <String>[
    'uv',
    'wind_speed',
    'wind_direction',
    'soil',
    'rain'
  ];
  String _crop = 'Wheat';
  String _cropStage = 'Flowering';
  bool _smartIrrigationEnabled = false;

  static const List<IrrigationCropOption> _presetOptions =
      <IrrigationCropOption>[
    IrrigationCropOption(
      crop: 'Wheat',
      stages: <String>['Germination', 'Tillering', 'Flowering', 'Maturity'],
    ),
    IrrigationCropOption(
      crop: 'Rice',
      stages: <String>[
        'Nursery / Establishment',
        'Tillering',
        'Panicle Initiation / Flowering',
        'Grain Filling / Maturity',
      ],
    ),
    IrrigationCropOption(
      crop: 'Maize',
      stages: <String>[
        'Germination',
        'Vegetative',
        'Flowering / Pollination',
        'Maturity',
      ],
    ),
    IrrigationCropOption(
      crop: 'Cotton',
      stages: <String>[
        'Germination',
        'Vegetative / Squaring',
        'Flowering / Boll Formation',
        'Maturity',
      ],
    ),
  ];

  @override
  AppDataMode get mode => AppDataMode.mock;

  @override
  String get modeLabel => 'Demo Data';

  @override
  Future<GpsReading?> fetchLatestGpsReading() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final reading = GpsReading(
      id: 1,
      stationId: 1,
      recordedAt: DateTime.now(),
      latitude: 24.8607 + (math.Random().nextDouble() - 0.5) * 0.01,
      longitude: 67.0011 + (math.Random().nextDouble() - 0.5) * 0.01,
      altitudeM: 15.0,
      speedKmh: 0.0,
      headingDeg: 0.0,
    );
    return reading;
  }

  @override
  Future<SensorReading> fetchLatestReading() async {
    _tick += 1;
    return _buildReading(_tick);
  }

  @override
  Future<StationSummary> fetchSummary({int hours = 24}) async {
    final reading = _buildReading(_tick);
    return StationSummary(
      deviceId: deviceId,
      hours: hours,
      totalReadings: 480,
      lastRecordedAt: reading.recordedAt,
      averages: {
        'ws': 1.8,
        'moist': 24.8,
        'temp': 21.2,
        'rain': 0.1,
        'solar': 3.8,
      },
    );
  }

  @override
  Future<MonitoringStatus> fetchMonitoringStatus() async {
    _tick += 1;
    final reading = _buildReading(_tick);
    final conditions = _buildConditions(reading);
    final alerts = _buildAlerts(reading, conditions);

    SensorHealth healthFor(String key) {
      final enabled = _sensorEnabled[key] ?? false;
      if (!enabled) {
        return const SensorHealth(
            status: 'disabled', freshness: 'disabled', lastUpdated: null);
      }
      return SensorHealth(
          status: 'online',
          freshness: 'fresh',
          lastUpdated: reading.recordedAt);
    }

    return MonitoringStatus(
      deviceId: deviceId,
      stationName: stationName,
      lastUpdated: reading.recordedAt,
      overallStatus: alerts.any((alert) => alert.severity == 'critical')
          ? 'critical'
          : alerts.any((alert) => alert.severity == 'warning')
              ? 'attention'
              : 'normal',
      sensorHealth: {
        'wind': SensorHealth(
          status: (_sensorEnabled['wind_speed'] ?? false) ||
                  (_sensorEnabled['wind_direction'] ?? false)
              ? 'online'
              : 'disabled',
          freshness: (_sensorEnabled['wind_speed'] ?? false) ||
                  (_sensorEnabled['wind_direction'] ?? false)
              ? 'fresh'
              : 'disabled',
          lastUpdated: (_sensorEnabled['wind_speed'] ?? false) ||
                  (_sensorEnabled['wind_direction'] ?? false)
              ? reading.recordedAt
              : null,
        ),
        'soil': healthFor('soil'),
        'rain': healthFor('rain'),
        'uv': healthFor('uv'),
      },
      conditions: conditions,
      alerts: alerts,
      latest: reading,
    );
  }

  @override
  Future<StationTrends> fetchTrends({int hours = 24}) async {
    final now = DateTime.now();

    List<TrendPoint> seriesFor(double base, double swing,
        {double shift = 0, double floor = 0}) {
      return List<TrendPoint>.generate(hours, (index) {
        final pointTime = now.subtract(Duration(hours: hours - index));
        final wave = math.sin((index + shift) / 3.4);
        final value = math.max(floor, base + (wave * swing));
        return TrendPoint(
            timestamp: pointTime,
            value: double.parse(value.toStringAsFixed(1)));
      });
    }

    return StationTrends(
      deviceId: deviceId,
      hours: hours,
      series: {
        'moist': seriesFor(24.0, 3.4, shift: 0.4, floor: 16),
        'temp': seriesFor(21.0, 4.6, shift: 1.2, floor: 12),
        'rain': List<TrendPoint>.generate(hours, (index) {
          final pointTime = now.subtract(Duration(hours: hours - index));
          final value = index % 9 == 0 ? 0.6 : 0.0;
          return TrendPoint(timestamp: pointTime, value: value);
        }),
        'ws': seriesFor(2.1, 1.3, shift: 2.4, floor: 0),
        'uv': seriesFor(4.2, 2.5, shift: 1.8, floor: 0),
        'ec': seriesFor(20.5, 1.4, shift: 0.8, floor: 10),
        'ph': seriesFor(0.55, 0.05, shift: 1.1, floor: 0.3),
        'n': seriesFor(20.0, 5.0, shift: 0.6, floor: 8),
        'p': seriesFor(1.5, 0.6, shift: 1.8, floor: 0.3),
        'k': seriesFor(2.1, 0.8, shift: 2.2, floor: 0.5),
      },
    );
  }

  SensorReading _buildReading(int tick) {
    final now = DateTime.now();
    final wave = math.sin(tick / 4);
    final moist = double.parse((24 + (wave * 4)).toStringAsFixed(1));
    final temp =
        double.parse((20 + (math.sin((tick + 2) / 5) * 4)).toStringAsFixed(1));
    final ws = double.parse((1.5 + (math.cos((tick + 1) / 3.8) * 1.4))
        .clamp(0.0, 7.5)
        .toStringAsFixed(1));
    final uv = double.parse((4 + (math.sin((tick + 3) / 3) * 2.8))
        .clamp(0.0, 9.0)
        .toStringAsFixed(1));
    final rain = tick % 16 == 0 ? 0.8 : 0.0;
    final ec =
        double.parse((20.5 + (math.cos(tick / 5.5) * 1.2)).toStringAsFixed(1));
    final directionIndex = tick % 16;
    const directions = [
      'N',
      'NNE',
      'NE',
      'ENE',
      'E',
      'ESE',
      'SE',
      'SSE',
      'S',
      'SSW',
      'SW',
      'WSW',
      'W',
      'WNW',
      'NW',
      'NNW'
    ];

    return SensorReading(
      id: 9000 + tick,
      deviceId: deviceId,
      stationName: stationName,
      recordedAt: now,
      receivedAt: now,
      ws: (_sensorEnabled['wind_speed'] ?? false) ? ws : null,
      wdDeg: (_sensorEnabled['wind_direction'] ?? false)
          ? directionIndex * 22.5
          : null,
      wdDir: (_sensorEnabled['wind_direction'] ?? false)
          ? directions[directionIndex]
          : null,
      moist: (_sensorEnabled['soil'] ?? false) ? moist : null,
      temp: (_sensorEnabled['soil'] ?? false) ? temp : null,
      ec: (_sensorEnabled['soil'] ?? false) ? ec : null,
      n: (_sensorEnabled['soil'] ?? false) ? 20.0 : null,
      p: (_sensorEnabled['soil'] ?? false) ? 1.5 : null,
      k: (_sensorEnabled['soil'] ?? false) ? 2.1 : null,
      ph: (_sensorEnabled['soil'] ?? false) ? 0.53 : null,
      rain: (_sensorEnabled['rain'] ?? false) ? rain : null,
      solar: (_sensorEnabled['uv'] ?? false) ? uv : null,
    );
  }

  Map<String, String> _buildConditions(SensorReading reading) {
    return {
      'soil_moisture':
          reading.moist != null && reading.moist! < 20 ? 'low' : 'normal',
      'temperature':
          reading.temp != null && reading.temp! > 35 ? 'hot' : 'normal',
      'rain': reading.rain != null && reading.rain! > 0
          ? 'detected'
          : 'not_detected',
      'wind': reading.ws != null && reading.ws! > 5 ? 'moderate' : 'calm',
      'uv': reading.solar != null && reading.solar! > 6
          ? 'high'
          : reading.solar != null && reading.solar! > 3
              ? 'moderate'
              : 'low',
      'ec': reading.ec != null && reading.ec! > 30 ? 'high' : 'normal',
    };
  }

  List<MonitoringAlert> _buildAlerts(
      SensorReading reading, Map<String, String> conditions) {
    final alerts = <MonitoringAlert>[];

    if (conditions['soil_moisture'] == 'low') {
      alerts.add(
        MonitoringAlert(
          type: 'low_moisture',
          severity: 'warning',
          title: 'Low Soil Moisture',
          message:
              'Mock field moisture has dropped below the recommended range.',
          timestamp: reading.recordedAt,
        ),
      );
    }

    if (conditions['rain'] == 'detected') {
      alerts.add(
        MonitoringAlert(
          type: 'rain_detected',
          severity: 'info',
          title: 'Rain Detected',
          message:
              'Demo rainfall event is active in the current mock scenario.',
          timestamp: reading.recordedAt,
        ),
      );
    }

    if (conditions['uv'] == 'high') {
      alerts.add(
        MonitoringAlert(
          type: 'high_uv',
          severity: 'warning',
          title: 'High UV Exposure',
          message: 'Mock UV exposure is elevated and should be monitored.',
          timestamp: reading.recordedAt,
        ),
      );
    }

    return alerts;
  }

  @override
  Future<StationSettings> fetchSettings() async {
    return StationSettings(
      deviceId: deviceId,
      stationName: stationName,
      sensors: StationSensorSettings(
        windSpeedEnabled: _sensorEnabled['wind_speed'] ?? false,
        windDirectionEnabled: _sensorEnabled['wind_direction'] ?? false,
        soilEnabled: _sensorEnabled['soil'] ?? false,
        rainEnabled: _sensorEnabled['rain'] ?? false,
        uvEnabled: _sensorEnabled['uv'] ?? false,
      ),
      polling: StationPollingSettings(
        pollIntervalSeconds: _pollIntervalSeconds,
        interReadDelayMs: _interReadDelayMs,
        sensorReadOrder: _sensorReadOrder,
        sensorIntervals: <String, SensorIntervalSettings>{
          for (final entry in _sensorIntervals.entries)
            entry.key: SensorIntervalSettings(
              enabled: entry.key == 'wind'
                  ? ((_sensorEnabled['wind_speed'] ?? false) ||
                      (_sensorEnabled['wind_direction'] ?? false))
                  : (_sensorEnabled[entry.key] ?? false),
              intervalSeconds: entry.value,
            ),
        },
      ),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<StationSettings> patchSettings(StationSettingsPatch patch) async {
    if (patch.sensorEnabled != null) {
      patch.sensorEnabled!.forEach((key, enabled) {
        if (key == 'wind') {
          _sensorEnabled['wind_speed'] = enabled;
          _sensorEnabled['wind_direction'] = enabled;
        } else {
          _sensorEnabled[key] = enabled;
        }
      });
    }
    if (patch.pollIntervalSeconds != null) {
      final value = patch.pollIntervalSeconds!;
      _pollIntervalSeconds = value < 1
          ? 1
          : value > 3600
              ? 3600
              : value;
    }
    if (patch.interReadDelayMs != null) {
      final value = patch.interReadDelayMs!;
      _interReadDelayMs = value < 0
          ? 0
          : value > 5000
              ? 5000
              : value;
    }
    if (patch.sensorReadOrder != null && patch.sensorReadOrder!.isNotEmpty) {
      _sensorReadOrder = patch.sensorReadOrder!;
    }
    patch.sensorIntervals?.forEach((key, value) {
      final normalized = key == 'solar' ? 'uv' : key;
      _sensorIntervals[normalized] = value < 1 ? 1 : value;
    });
    return fetchSettings();
  }

  @override
  Future<List<IrrigationCropOption>> fetchIrrigationPresets() async {
    return _presetOptions;
  }

  @override
  Future<IrrigationProfile> fetchIrrigationProfile() async {
    return _buildProfile();
  }

  @override
  Future<IrrigationProfile> patchIrrigationProfile(
      IrrigationProfilePatch patch) async {
    final nextCrop = patch.crop ?? _crop;
    final cropOption = _presetOptions.firstWhere(
      (option) => option.crop == nextCrop,
      orElse: () => _presetOptions.first,
    );
    final nextStage = patch.cropStage ?? _cropStage;

    _crop = cropOption.crop;
    _cropStage = cropOption.stages.contains(nextStage)
        ? nextStage
        : cropOption.stages.first;
    _smartIrrigationEnabled =
        patch.smartIrrigationEnabled ?? _smartIrrigationEnabled;
    if (patch.crop != null || patch.cropStage != null) {
      _smartIrrigationEnabled = patch.smartIrrigationEnabled ?? true;
    }

    return _buildProfile();
  }

  @override
  Future<IrrigationAdvisory?> fetchLatestIrrigationAdvisory() async {
    if (!_smartIrrigationEnabled) {
      return null;
    }
    final reading = _buildReading(_tick);
    final profile = _buildProfile();
    final isDry =
        reading.moist != null && reading.moist! < profile.moistureLowerTarget;
    final hasRain =
        reading.rain != null && reading.rain! >= profile.effectiveRainMm;
    final decision = isDry && !hasRain
        ? 'start_irrigation'
        : hasRain
            ? 'delay_irrigation'
            : 'no_irrigation_needed';

    return IrrigationAdvisory(
      id: 7000 + _tick,
      deviceId: deviceId,
      stationName: stationName,
      readingId: reading.id,
      generatedAt: DateTime.now(),
      decision: decision,
      urgency: decision == 'start_irrigation' ? 'medium' : 'none',
      dataStatus: 'fresh',
      title: decision == 'start_irrigation'
          ? 'Start irrigation now'
          : decision == 'delay_irrigation'
              ? 'Delay irrigation'
              : 'No irrigation needed',
      message: decision == 'start_irrigation'
          ? 'Soil moisture is below the target band for $_crop at $_cropStage.'
          : decision == 'delay_irrigation'
              ? 'Recent rainfall can reduce the immediate irrigation need.'
              : 'Soil moisture is within the target band for $_crop at $_cropStage.',
      reason:
          'Demo advisory uses crop stage moisture thresholds and current mock sensor readings.',
      conditionSummary: decision,
      factors: <String, dynamic>{
        'soil_moisture': <String, dynamic>{
          'value': reading.moist,
          'unit': '%',
          'lower_target': profile.moistureLowerTarget,
          'upper_target': profile.moistureUpperTarget,
        },
      },
      profileSnapshot: <String, dynamic>{
        'crop': _crop,
        'crop_stage': _cropStage,
      },
    );
  }

  @override
  Future<Stream<SensorReading>?> connectRealtime() async => null;

  @override
  void disposeRealtime() {}

  IrrigationProfile _buildProfile() {
    final criticalStage = _cropStage.toLowerCase().contains('flower');
    final lower = criticalStage ? 55.0 : 45.0;
    final upper = criticalStage ? 85.0 : 75.0;
    return IrrigationProfile(
      id: 1,
      deviceId: deviceId,
      stationName: stationName,
      crop: _crop,
      cropStage: _cropStage,
      smartIrrigationEnabled: _smartIrrigationEnabled,
      moistureLowerTarget: lower,
      moistureUpperTarget: upper,
      effectiveRainMm: 2,
      rainWindowHours: 6,
      highTempC: 35,
      highSolarWm2: 700,
      highWindMs: 6,
      staleAfterMinutes: 15,
      updatedAt: DateTime.now(),
    );
  }
}
