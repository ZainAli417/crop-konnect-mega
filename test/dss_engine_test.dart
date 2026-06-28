import 'package:ess_sensor_ck/src/models/dss.dart';
import 'package:ess_sensor_ck/src/models/sensor_reading.dart';
import 'package:ess_sensor_ck/src/services/dss_crop_repository.dart';
import 'package:ess_sensor_ck/src/services/dss_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DSS crop dataset loads at full scale', () async {
    final profiles = await DssCropKnowledgeRepository().loadProfiles();

    expect(profiles.length, greaterThanOrEqualTo(100));
    expect(profiles.every((profile) => profile.stages.isNotEmpty), isTrue);
    expect(profiles.every((profile) => profile.phMax > profile.phMin), isTrue);
    expect(
      profiles.every((profile) => profile.ecThresholdDsM > 0),
      isTrue,
    );

    final wheat = DssCropKnowledgeRepository().resolveCrop(profiles, 'Wheat');
    expect(wheat.name, 'Wheat');
    expect(wheat.stages.any((stage) => stage.name == 'Flowering'), isTrue);
  });

  test('DSS raises heat and low-moisture crop stress action', () {
    final analysis = const DssEngine().analyze(
      DssInput(
        crop: _wheat,
        stage: _flowering,
        reading: SensorReading(
          id: 1,
          deviceId: 'TEST',
          stationName: 'Test Station',
          recordedAt: _freshTime,
          receivedAt: _freshTime,
          ws: 3,
          wdDeg: 90,
          wdDir: 'E',
          moist: 32,
          temp: 38,
          ec: 1100,
          n: 50,
          p: 28,
          k: 110,
          ph: 6.8,
          rain: 0,
          solar: 760,
        ),
        trends: null,
        monitoring: null,
        irrigationProfile: null,
      ),
    );

    expect(analysis.fieldScore.value, lessThan(80));
    expect(
      analysis.allRecommendations.any(
        (recommendation) => recommendation.id == 'crop_stress_heat_dry',
      ),
      isTrue,
    );
    expect(analysis.priorityRecommendations.first.urgency, DssUrgency.high);
  });

  test('DSS blocks spraying when wind is too high', () {
    final analysis = const DssEngine().analyze(
      DssInput(
        crop: _wheat,
        stage: _flowering,
        reading: SensorReading(
          id: 2,
          deviceId: 'TEST',
          stationName: 'Test Station',
          recordedAt: _freshTime,
          receivedAt: _freshTime,
          ws: 6,
          wdDeg: 90,
          wdDir: 'E',
          moist: 64,
          temp: 28,
          ec: 1000,
          n: 55,
          p: 30,
          k: 120,
          ph: 6.8,
          rain: 0,
          solar: 500,
        ),
        trends: null,
        monitoring: null,
        irrigationProfile: null,
      ),
    );

    final spray = analysis.allRecommendations.singleWhere(
      (recommendation) => recommendation.id == 'spray_window_bad',
    );
    expect(spray.title, 'Do not spray now');
    expect(spray.urgency, DssUrgency.high);
  });

  test('DSS lowers confidence for stale sensor data', () {
    final oldTime = DateTime.now().subtract(const Duration(hours: 2));
    final analysis = const DssEngine().analyze(
      DssInput(
        crop: _wheat,
        stage: _flowering,
        reading: SensorReading(
          id: 3,
          deviceId: 'TEST',
          stationName: 'Test Station',
          recordedAt: oldTime,
          receivedAt: oldTime,
          ws: 2,
          wdDeg: 90,
          wdDir: 'E',
          moist: 64,
          temp: 28,
          ec: 1000,
          n: 55,
          p: 30,
          k: 120,
          ph: 6.8,
          rain: 0,
          solar: 500,
        ),
        trends: null,
        monitoring: null,
        irrigationProfile: null,
      ),
    );

    expect(analysis.dataConfidence, DssConfidence.low);
    expect(
      analysis.allRecommendations.any(
        (recommendation) => recommendation.id == 'sensor_stale',
      ),
      isTrue,
    );
  });
}

final _freshTime = DateTime.now();

const _flowering = DssCropStage(
  name: 'Flowering',
  moistureLower: 55,
  moistureUpper: 85,
  sensitivity: 'high',
  nDemand: 'high',
  pDemand: 'high',
  kDemand: 'high',
  actionNote: 'This is a sensitive yield stage.',
);

const _wheat = DssCropProfile(
  id: 'wheat',
  name: 'Wheat',
  group: 'cereal',
  aliases: ['gandum'],
  pakistanRegions: ['Punjab', 'Sindh'],
  seasons: ['Rabi'],
  phMin: 6.0,
  phMax: 7.8,
  ecThresholdDsM: 4.0,
  salinityTolerance: 'moderate',
  tempOptimalMinC: 15,
  tempOptimalMaxC: 28,
  tempHotC: 34,
  tempColdC: 5,
  nDemand: 'high',
  pDemand: 'medium',
  kDemand: 'medium',
  diseaseTempMinC: 15,
  diseaseTempMaxC: 28,
  pestRisk: 'medium',
  stages: [_flowering],
  notes: 'Test wheat profile.',
  confidence: 'medium',
  sources: ['test'],
);
