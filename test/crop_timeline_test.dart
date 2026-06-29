import 'package:ess_sensor_ck/src/models/dss.dart';
import 'package:ess_sensor_ck/src/models/sensor_reading.dart';
import 'package:ess_sensor_ck/src/services/crop_timeline_repository.dart';
import 'package:ess_sensor_ck/src/services/dss_crop_repository.dart';
import 'package:ess_sensor_ck/src/services/dss_engine.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.now();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('crop timelines load with ordered day-range stages', () async {
    final timelines = await CropTimelineRepository().load();
    expect(timelines.length, greaterThanOrEqualTo(32));

    for (final t in timelines) {
      expect(t.stages, isNotEmpty);
      expect(t.totalDays, greaterThan(0));
      var prevEnd = -1;
      for (final s in t.stages) {
        expect(s.startDay, lessThanOrEqualTo(s.endDay));
        // stages are ordered through the cycle
        expect(s.startDay, greaterThanOrEqualTo(prevEnd));
        expect(s.moistureLower, lessThan(s.moistureUpper));
        prevEnd = s.endDay;
      }
    }
  });

  test('growth stage is computed from days after sowing', () async {
    final repo = CropTimelineRepository();
    final timelines = await repo.load();
    final wheat = repo.resolve(timelines, 'wheat');

    final first = wheat.stageForDay(0);
    final last = wheat.stageForDay(wheat.totalDays + 50);
    expect(first.startDay, 0);
    expect(last, wheat.stages.last);
    expect(wheat.isPastHarvest(wheat.totalDays + 1), isTrue);

    // a mid-cycle day lands inside one stage's window
    final mid = wheat.totalDays ~/ 2;
    final midStage = wheat.stageForDay(mid);
    expect(mid, inInclusiveRange(midStage.startDay, midStage.endDay));
  });

  test('advice is firm — no low-confidence or advisory hedging in cards', () async {
    final profiles = await DssCropKnowledgeRepository().loadProfiles();
    final crop = DssCropKnowledgeRepository().resolveCrop(profiles, 'Wheat');
    final timelines = await CropTimelineRepository().load();
    final wheat = CropTimelineRepository().resolve(timelines, 'wheat');
    final tStage = wheat.stageForDay(100);
    final stage = DssCropStage(
      name: tStage.name,
      moistureLower: tStage.moistureLower,
      moistureUpper: tStage.moistureUpper,
      sensitivity: tStage.sensitivity,
      nDemand: tStage.nDemand,
      pDemand: tStage.pDemand,
      kDemand: tStage.kDemand,
      actionNote: tStage.focus,
      startDay: tStage.startDay,
      endDay: tStage.endDay,
      tempOptMin: tStage.tempOptMin,
      tempOptMax: tStage.tempOptMax,
      icon: tStage.icon,
    );

    final analysis = const DssEngine().analyze(
      DssInput(
        crop: crop,
        stage: stage,
        reading: SensorReading(
          id: 9,
          deviceId: 'TEST',
          stationName: 'Test',
          recordedAt: _now,
          receivedAt: _now,
          ws: 8,
          wdDeg: 90,
          wdDir: 'E',
          moist: 30,
          temp: 39,
          ec: 1200,
          n: 20,
          p: 10,
          k: 40,
          ph: 8.6,
          rain: 0,
          solar: 850,
        ),
        trends: null,
        monitoring: null,
        irrigationProfile: null,
        daysAfterSowing: 100,
        cycleDays: 180,
      ),
    );

    final blob = analysis.allRecommendations
        .expand((r) => [r.title, r.decision, r.whyItMatters, r.farmerAction])
        .join(' ')
        .toLowerCase();
    expect(blob.contains('confidence'), isFalse);
    expect(blob.contains('advisory'), isFalse);
    // every module carries a score in range
    for (final m in analysis.modules) {
      expect(m.score, inInclusiveRange(0, 100));
    }
    // this clearly-stressed field should not read as healthy
    expect(analysis.fieldScore.value, lessThan(70));
  });
}
