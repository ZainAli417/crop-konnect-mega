import '../models/dss.dart';
import '../models/monitoring_status.dart';
import '../models/station_trends.dart';

class DssEngine {
  const DssEngine();

  DssAnalysis analyze(DssInput input) {
    final dataConfidence = _dataConfidence(input);
    final modules = <DssModuleResult>[
      _sensorConfidence(input, dataConfidence),
      _irrigationDecision(input, dataConfidence),
      _cropStress(input, dataConfidence),
      _soilHealth(input, dataConfidence),
      _nutrients(input, dataConfidence),
      _phSuitability(input, dataConfidence),
      _salinity(input, dataConfidence),
      _sprayTiming(input, dataConfidence),
      _pestDisease(input, dataConfidence),
      _stageReadiness(input, dataConfidence),
    ];

    final fieldScore = _fieldHealthScore(modules);
    final recommendations = modules
        .expand((module) => module.recommendations)
        .toList(growable: false)
      ..sort(_compareRecommendations);

    return DssAnalysis(
      generatedAt: DateTime.now(),
      crop: input.crop,
      stage: input.stage,
      fieldScore: fieldScore,
      priorityRecommendations:
          recommendations.take(3).toList(growable: false),
      modules: modules,
      dataConfidence: dataConfidence,
      sourceSummary:
          'Uses live station sensors, crop-stage targets, FAO-style water balance concepts, soil-test interpretation rules, salinity tolerance classes, and spray-weather safety rules.',
    );
  }

  DssModuleResult _sensorConfidence(
    DssInput input,
    DssConfidence confidence,
  ) {
    final reading = input.reading;
    var penalty = 0;
    final recs = <DssRecommendation>[];
    final evidence = <DssEvidence>[];

    if (reading == null) {
      penalty += 80;
      evidence.add(const DssEvidence(
        label: 'Latest reading',
        value: 'Missing',
        status: 'critical',
      ));
      recs.add(_recommendation(
        id: 'sensor_missing',
        moduleId: 'sensor_confidence',
        moduleTitle: 'Sensor Confidence',
        title: 'No fresh field data is available',
        decision: 'Check station connection before acting',
        urgency: DssUrgency.high,
        confidence: DssConfidence.high,
        why:
            'A DSS decision is only useful when it is based on fresh field readings.',
        action:
            'Open the station area and confirm the logger, power, network, and soil probe are working.',
        check: 'Look for physical damage, loose cables, or a dead battery.',
        evidence: evidence,
      ));
    } else {
      final staleMinutes =
          (input.irrigationProfile?.staleAfterMinutes ?? 15)
              .clamp(5, 120)
              .toInt();
      final age = DateTime.now().difference(reading.recordedAt).inMinutes;
      final fresh = age <= staleMinutes;
      evidence.add(DssEvidence(
        label: 'Data age',
        value: '$age min',
        status: fresh ? 'good' : 'warning',
      ));
      if (!fresh) {
        penalty += 35;
        recs.add(_recommendation(
          id: 'sensor_stale',
          moduleId: 'sensor_confidence',
          moduleTitle: 'Sensor Confidence',
          title: 'Decision confidence is reduced',
          decision: 'Verify the field before acting',
          urgency: DssUrgency.moderate,
          confidence: DssConfidence.high,
          why:
              'The latest reading is older than the station freshness window.',
          action:
              'Refresh the logger and confirm the current soil condition before making costly farm actions.',
          check: 'Check logger time, network signal, and sensor probe contact.',
          evidence: evidence,
        ));
      }

      final missing = <String>[
        if (reading.moist == null) 'moisture',
        if (reading.temp == null) 'temperature',
        if (reading.ec == null) 'EC',
        if (reading.ph == null) 'pH',
        if (reading.n == null) 'N',
        if (reading.p == null) 'P',
        if (reading.k == null) 'K',
        if (reading.ws == null) 'wind',
        if (reading.rain == null) 'rain',
      ];
      penalty += missing.length * 5;
      evidence.add(DssEvidence(
        label: 'Missing sensors',
        value: missing.isEmpty ? 'None' : missing.join(', '),
        status: missing.length <= 2 ? 'good' : 'warning',
      ));
      if (missing.length >= 4) {
        recs.add(_recommendation(
          id: 'sensor_gaps',
          moduleId: 'sensor_confidence',
          moduleTitle: 'Sensor Confidence',
          title: 'Several readings are missing',
          decision: 'Treat DSS advice as a field-check reminder',
          urgency: DssUrgency.moderate,
          confidence: DssConfidence.high,
          why:
              'Missing readings reduce the accuracy of stress, nutrient, spray, and soil decisions.',
          action:
              'Use the recommendation list as a priority checklist, then confirm the crop condition manually.',
          check: 'Inspect disabled sensors and recent logger configuration changes.',
          evidence: evidence,
        ));
      }
    }

    return DssModuleResult(
      id: 'sensor_confidence',
      title: 'Sensor Confidence',
      score: _score(100 - penalty),
      status: penalty <= 15 ? 'Reliable' : penalty <= 45 ? 'Caution' : 'Weak',
      summary: penalty <= 15
          ? 'Data is fresh enough for normal DSS guidance.'
          : 'Use DSS advice with field confirmation today.',
      recommendations: recs,
    );
  }

  DssModuleResult _irrigationDecision(
    DssInput input,
    DssConfidence confidence,
  ) {
    final r = input.reading;
    var penalty = 0;
    final recs = <DssRecommendation>[];
    final moisture = r?.moist;
    final rain = r?.rain;
    final temp = r?.temp;
    final lowMoisture =
        moisture != null && moisture < input.stage.moistureLower;
    final highMoisture =
        moisture != null && moisture > input.stage.moistureUpper;
    final rainDetected = rain != null && rain > 0;
    final hot = temp != null && temp >= input.crop.tempHotC;

    if (lowMoisture) penalty += _sensitivePenalty(input.stage, 30);
    if (hot && lowMoisture) penalty += 12;
    if (highMoisture || rainDetected) penalty += 8;

    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'Moisture',
        value: _metric(moisture, '%'),
        status: lowMoisture
            ? 'low'
            : highMoisture
                ? 'high'
                : 'ok',
      ),
      DssEvidence(
        label: 'Target',
        value:
            '${_fixed(input.stage.moistureLower)}-${_fixed(input.stage.moistureUpper)}%',
        status: 'crop stage',
      ),
      DssEvidence(
        label: 'Rain',
        value: _metric(rain, 'mm'),
        status: rainDetected ? 'detected' : 'clear',
      ),
      DssEvidence(
        label: 'Temperature',
        value: _metric(temp, 'C'),
        status: hot ? 'hot' : 'ok',
      ),
    ];

    if (lowMoisture && !rainDetected) {
      recs.add(_recommendation(
        id: 'irrigation_needed',
        moduleId: 'irrigation_decision',
        moduleTitle: 'Irrigation Decision',
        title: 'Plan irrigation check',
        decision: hot
            ? 'Moisture is low and heat is increasing water stress'
            : 'Moisture is below the crop-stage target',
        urgency: hot ? DssUrgency.high : DssUrgency.moderate,
        confidence: confidence,
        why:
            '${input.crop.name} at ${input.stage.name} should stay near the target moisture band. Low moisture can reduce growth and yield, especially during sensitive stages.',
        action:
            'Check the field and prepare irrigation if the soil confirms the sensor reading. Avoid over-irrigation.',
        check:
            'Feel soil near the root zone, check dry patches, and confirm the irrigation line or water source is ready.',
        evidence: evidence,
      ));
    } else if (rainDetected || highMoisture) {
      recs.add(_recommendation(
        id: 'irrigation_hold',
        moduleId: 'irrigation_decision',
        moduleTitle: 'Irrigation Decision',
        title: 'Hold irrigation for now',
        decision: rainDetected
            ? 'Rain is detected, so extra irrigation may waste water'
            : 'Moisture is above the crop-stage target',
        urgency: DssUrgency.low,
        confidence: confidence,
        why:
            'Too much water can waste resources and may increase disease or root stress.',
        action:
            'Wait and keep monitoring unless field inspection shows dry areas not captured by the probe.',
        check:
            'Check for standing water, blocked drainage, or uneven irrigation coverage.',
        evidence: evidence,
      ));
    }

    return DssModuleResult(
      id: 'irrigation_decision',
      title: 'Irrigation Decision',
      score: _score(100 - penalty),
      status: lowMoisture
          ? 'Needs Check'
          : rainDetected || highMoisture
              ? 'Hold'
              : 'In Range',
      summary: lowMoisture
          ? 'Moisture is below the selected crop-stage target.'
          : rainDetected || highMoisture
              ? 'Water is available or moisture is above target.'
              : 'Moisture is inside the selected target band.',
      recommendations: recs,
    );
  }

  DssModuleResult _cropStress(DssInput input, DssConfidence confidence) {
    final r = input.reading;
    var penalty = 0;
    final recs = <DssRecommendation>[];
    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'Crop stage',
        value: input.stage.name,
        status: input.stage.sensitivity,
      ),
    ];

    final moisture = r?.moist;
    final temp = r?.temp;
    final solar = r?.solar;
    final wind = r?.ws;
    final moistureTrend = _trendDelta(input.trends, 'moist');
    final tempAverage = _trendAverage(input.trends, 'temp');

    final lowMoisture =
        moisture != null && moisture < input.stage.moistureLower;
    final hot = temp != null && temp >= input.crop.tempHotC;
    final highSolar = solar != null && solar >= 700;
    final dryingWind = wind != null && wind >= 6;
    final moistureFalling =
        moistureTrend != null && moistureTrend <= -8;
    final sustainedHeat =
        tempAverage != null && tempAverage >= input.crop.tempHotC - 2;

    if (lowMoisture) penalty += _sensitivePenalty(input.stage, 26);
    if (hot) penalty += _sensitivePenalty(input.stage, 24);
    if (highSolar) penalty += 12;
    if (dryingWind) penalty += 10;
    if (moistureFalling) penalty += 8;
    if (sustainedHeat) penalty += 8;

    evidence.addAll([
      DssEvidence(
        label: 'Moisture',
        value: _metric(moisture, '%'),
        status: lowMoisture ? 'low' : 'ok',
      ),
      DssEvidence(
        label: 'Stage target',
        value:
            '${_fixed(input.stage.moistureLower)}-${_fixed(input.stage.moistureUpper)}%',
        status: 'target',
      ),
      DssEvidence(
        label: 'Soil temp',
        value: _metric(temp, 'C'),
        status: hot ? 'hot' : 'ok',
      ),
      DssEvidence(
        label: 'Solar',
        value: _metric(solar, 'W/m2'),
        status: highSolar ? 'high' : 'ok',
      ),
      DssEvidence(
        label: '24h moisture trend',
        value: moistureTrend == null
            ? 'Missing'
            : '${moistureTrend >= 0 ? '+' : ''}${_fixed(moistureTrend)}%',
        status: moistureFalling ? 'falling' : 'ok',
      ),
    ]);

    if (lowMoisture && hot) {
      recs.add(_recommendation(
        id: 'crop_stress_heat_dry',
        moduleId: 'crop_stress',
        moduleTitle: 'Crop Stress',
        title: 'Check the crop today',
        decision: 'Heat and low moisture are stressing the plant',
        urgency: DssUrgency.high,
        confidence: confidence,
        why:
            '${input.crop.name} is in ${input.stage.name}. This stage can lose yield faster when moisture is below target and temperature is high.',
        action:
            'Inspect the crop in the field and reduce avoidable stress today. Keep irrigation planning active, avoid unnecessary tillage, and protect young or sensitive plants where possible.',
        check:
            'Look for leaf curling, dull color, wilting during midday, and dry soil near the active root zone.',
        evidence: evidence,
      ));
    } else if (lowMoisture || hot || highSolar) {
      recs.add(_recommendation(
        id: 'crop_stress_watch',
        moduleId: 'crop_stress',
        moduleTitle: 'Crop Stress',
        title: 'Crop stress risk is building',
        decision: 'Watch the field closely',
        urgency: lowMoisture || hot ? DssUrgency.moderate : DssUrgency.low,
        confidence: confidence,
        why:
            'One or more stress signals are outside the comfortable range for this crop.',
        action:
            'Check the crop condition before the hottest part of the day and compare the sensor reading with actual soil feel.',
        check:
            'Look for wilting, leaf burn, poor flowering, or uneven patches.',
        evidence: evidence,
      ));
    }

    return DssModuleResult(
      id: 'crop_stress',
      title: 'Crop Stress',
      score: _score(100 - penalty),
      status: penalty >= 45 ? 'High Risk' : penalty >= 20 ? 'Watch' : 'Stable',
      summary: penalty >= 45
          ? 'Stress signals are strong for the selected crop stage.'
          : penalty >= 20
              ? 'Some stress signs need field checking.'
              : 'No major crop stress signal from current sensors.',
      recommendations: recs,
    );
  }

  DssModuleResult _soilHealth(DssInput input, DssConfidence confidence) {
    final r = input.reading;
    var penalty = 0;
    final recs = <DssRecommendation>[];
    final evidence = <DssEvidence>[];

    final ph = r?.ph;
    final ec = _ecDsM(r?.ec);
    final temp = r?.temp;
    final moisture = r?.moist;

    final phOut = ph != null &&
        (ph < input.crop.phMin - 0.2 || ph > input.crop.phMax + 0.2);
    final ecHigh = ec != null && ec >= input.crop.ecThresholdDsM;
    final tempHot = temp != null && temp >= input.crop.tempHotC;
    final tooDry = moisture != null && moisture < input.stage.moistureLower;

    if (phOut) penalty += 22;
    if (ecHigh) penalty += 24;
    if (tempHot) penalty += 16;
    if (tooDry) penalty += 18;

    evidence.addAll([
      DssEvidence(
        label: 'pH',
        value: _metric(ph, ''),
        status: phOut ? 'outside' : 'ok',
      ),
      DssEvidence(
        label: 'Preferred pH',
        value: '${_fixed(input.crop.phMin)}-${_fixed(input.crop.phMax)}',
        status: 'target',
      ),
      DssEvidence(
        label: 'EC',
        value: ec == null ? 'Missing' : '${_fixed(ec)} dS/m',
        status: ecHigh ? 'high' : 'ok',
      ),
      DssEvidence(
        label: 'Moisture',
        value: _metric(moisture, '%'),
        status: tooDry ? 'low' : 'ok',
      ),
    ]);

    if (phOut || ecHigh || tooDry) {
      recs.add(_recommendation(
        id: 'soil_health_attention',
        moduleId: 'soil_health',
        moduleTitle: 'Soil Health',
        title: 'Soil condition needs attention',
        decision: 'Confirm soil condition before input spending',
        urgency: ecHigh || phOut ? DssUrgency.moderate : DssUrgency.low,
        confidence: confidence,
        why:
            'pH, EC, and moisture affect how well roots can take up nutrients and water.',
        action:
            'Use the sensor result as a field-check signal. Confirm with a soil test before applying soil amendments.',
        check:
            'Check wet and dry patches, root health, crusting, and any white salt marks on the surface.',
        evidence: evidence,
      ));
    }

    return DssModuleResult(
      id: 'soil_health',
      title: 'Soil Health',
      score: _score(100 - penalty),
      status:
          penalty >= 45 ? 'Needs Work' : penalty >= 20 ? 'Caution' : 'Good',
      summary: penalty >= 45
          ? 'Several soil signals may limit crop performance.'
          : penalty >= 20
              ? 'Soil readings are usable but need checking.'
              : 'Soil condition is inside the broad target zone.',
      recommendations: recs,
    );
  }

  DssModuleResult _nutrients(DssInput input, DssConfidence confidence) {
    final r = input.reading;
    var penalty = 0;
    final recs = <DssRecommendation>[];
    final evidence = <DssEvidence>[];

    final nLow = _nutrientLow(r?.n, 'n', input.stage.nDemand);
    final pLow = _nutrientLow(r?.p, 'p', input.stage.pDemand);
    final kLow = _nutrientLow(r?.k, 'k', input.stage.kDemand);
    final ph = r?.ph;
    final phIssue =
        ph != null && (ph < input.crop.phMin || ph > input.crop.phMax);

    if (nLow) penalty += _demandPenalty(input.stage.nDemand, 18);
    if (pLow) penalty += _demandPenalty(input.stage.pDemand, 16);
    if (kLow) penalty += _demandPenalty(input.stage.kDemand, 16);
    if (phIssue) penalty += 12;

    evidence.addAll([
      DssEvidence(
        label: 'N index',
        value: _metric(r?.n, ''),
        status: nLow ? 'low' : 'ok',
      ),
      DssEvidence(
        label: 'P index',
        value: _metric(r?.p, ''),
        status: pLow ? 'low' : 'ok',
      ),
      DssEvidence(
        label: 'K index',
        value: _metric(r?.k, ''),
        status: kLow ? 'low' : 'ok',
      ),
      DssEvidence(
        label: 'Stage demand',
        value: 'N ${input.stage.nDemand}, P ${input.stage.pDemand}, K ${input.stage.kDemand}',
        status: 'stage',
      ),
    ]);

    if (nLow || pLow || kLow || phIssue) {
      recs.add(_recommendation(
        id: 'nutrient_review',
        moduleId: 'nutrients',
        moduleTitle: 'NPK Advisory',
        title: 'Review crop nutrition',
        decision: 'NPK sensor values need confirmation',
        urgency: nLow || pLow || kLow ? DssUrgency.moderate : DssUrgency.low,
        confidence:
            confidence == DssConfidence.high ? DssConfidence.medium : confidence,
        why:
            'NPK sensor readings are useful for trend direction, but fertilizer rates need local soil-test calibration.',
        action:
            'Check the crop color and growth. Confirm with a soil test or local agronomist before spending on fertilizer.',
        check:
            'Look for pale leaves, purple tint, weak stems, slow growth, or nutrient symptoms appearing in patches.',
        evidence: evidence,
      ));
    }

    return DssModuleResult(
      id: 'nutrients',
      title: 'NPK Advisory',
      score: _score(100 - penalty),
      status:
          penalty >= 40 ? 'Review Inputs' : penalty >= 18 ? 'Watch' : 'Balanced',
      summary: penalty >= 40
          ? 'Nutrient readings suggest a follow-up check.'
          : penalty >= 18
              ? 'One nutrient signal should be watched.'
              : 'No strong nutrient warning from current readings.',
      recommendations: recs,
    );
  }

  DssModuleResult _phSuitability(DssInput input, DssConfidence confidence) {
    final ph = input.reading?.ph;
    var penalty = 0;
    final recs = <DssRecommendation>[];
    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'pH',
        value: _metric(ph, ''),
        status: 'reading',
      ),
      DssEvidence(
        label: '${input.crop.name} range',
        value: '${_fixed(input.crop.phMin)}-${_fixed(input.crop.phMax)}',
        status: 'target',
      ),
    ];

    if (ph == null) {
      penalty += 15;
    } else if (ph < input.crop.phMin || ph > input.crop.phMax) {
      penalty += 36;
      recs.add(_recommendation(
        id: 'ph_outside_crop_range',
        moduleId: 'ph_suitability',
        moduleTitle: 'pH Suitability',
        title: 'Soil pH may reduce nutrient uptake',
        decision: 'Confirm pH before applying amendments',
        urgency: DssUrgency.moderate,
        confidence: confidence,
        why:
            '${input.crop.name} usually performs best near pH ${_fixed(input.crop.phMin)}-${_fixed(input.crop.phMax)}. Outside this band, nutrient availability can drop.',
        action:
            'Plan a soil-test confirmation and ask local extension support before liming or acidifying soil.',
        check:
            'Check whether poor growth is uniform across the field or concentrated in patches.',
        evidence: evidence,
      ));
    }

    return DssModuleResult(
      id: 'ph_suitability',
      title: 'pH Suitability',
      score: _score(100 - penalty),
      status: penalty >= 30 ? 'Outside Range' : penalty > 0 ? 'Missing' : 'Fit',
      summary: penalty >= 30
          ? 'pH is outside the broad crop preference band.'
          : penalty > 0
              ? 'pH reading is missing, so suitability is uncertain.'
              : 'pH is suitable for the selected crop.',
      recommendations: recs,
    );
  }

  DssModuleResult _salinity(DssInput input, DssConfidence confidence) {
    final ec = _ecDsM(input.reading?.ec);
    final ecTrend = _ecTrendDelta(input.trends);
    var penalty = 0;
    final recs = <DssRecommendation>[];
    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'EC',
        value: ec == null ? 'Missing' : '${_fixed(ec)} dS/m',
        status: 'reading',
      ),
      DssEvidence(
        label: 'Crop threshold',
        value: '${_fixed(input.crop.ecThresholdDsM)} dS/m',
        status: input.crop.salinityTolerance,
      ),
      DssEvidence(
        label: '24h EC trend',
        value: ecTrend == null
            ? 'Missing'
            : '${ecTrend >= 0 ? '+' : ''}${_fixed(ecTrend)} dS/m',
        status: ecTrend != null && ecTrend >= 0.5 ? 'rising' : 'ok',
      ),
    ];

    final caution = ec != null && ec >= input.crop.ecThresholdDsM * 0.8;
    final high = ec != null && ec >= input.crop.ecThresholdDsM;
    final rising = ecTrend != null && ecTrend >= 0.5;
    if (high) {
      penalty += 48;
    } else if (caution) {
      penalty += 24;
    } else if (rising) {
      penalty += 12;
    } else if (ec == null) {
      penalty += 12;
    }

    if (high || caution || rising) {
      recs.add(_recommendation(
        id: high
            ? 'salinity_high'
            : caution
                ? 'salinity_caution'
                : 'salinity_rising',
        moduleId: 'salinity',
        moduleTitle: 'Salinity / EC Risk',
        title: high ? 'Salinity risk is high' : 'Salinity risk is rising',
        decision: high
            ? 'Protect the root zone from salt stress'
            : 'Watch EC trend before it becomes costly',
        urgency: high
            ? DssUrgency.high
            : caution
                ? DssUrgency.moderate
                : DssUrgency.low,
        confidence: confidence,
        why:
            'High EC can make it harder for roots to take up water, so the crop can look thirsty even when soil is moist.',
        action:
            'Check irrigation water quality and drainage. Avoid unnecessary salt-forming inputs until EC is confirmed.',
        check:
            'Look for white surface crust, leaf edge burn, stunted patches, and poor germination areas.',
        evidence: evidence,
      ));
    }

    return DssModuleResult(
      id: 'salinity',
      title: 'Salinity / EC Risk',
      score: _score(100 - penalty),
      status: high
          ? 'High Risk'
          : caution || rising
              ? 'Caution'
              : 'Low Risk',
      summary: high
          ? 'EC is above the broad crop tolerance threshold.'
          : caution
              ? 'EC is close to the crop caution zone.'
              : rising
                  ? 'EC trend is rising and should be watched.'
              : 'No salinity warning from current EC.',
      recommendations: recs,
    );
  }

  DssModuleResult _sprayTiming(DssInput input, DssConfidence confidence) {
    final r = input.reading;
    var penalty = 0;
    final recs = <DssRecommendation>[];
    final windMs = r?.ws;
    final windMph = windMs == null ? null : windMs * 2.23694;
    final rain = r?.rain;
    final temp = r?.temp;
    final solar = r?.solar;

    final rainy = rain != null && rain > 0;
    final tooWindy = windMph != null && windMph > 10;
    final tooCalm = windMph != null && windMph < 3;
    final heatCaution = temp != null && temp >= 32;
    final solarCaution = solar != null && solar >= 800;

    if (rainy) penalty += 40;
    if (tooWindy) penalty += 36;
    if (tooCalm) penalty += 18;
    if (heatCaution) penalty += 15;
    if (solarCaution) penalty += 10;

    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'Wind',
        value: windMph == null ? 'Missing' : '${_fixed(windMph)} mph',
        status: tooWindy ? 'high' : tooCalm ? 'too calm' : 'ok',
      ),
      DssEvidence(
        label: 'Rain',
        value: _metric(rain, 'mm'),
        status: rainy ? 'detected' : 'clear',
      ),
      DssEvidence(
        label: 'Temp',
        value: _metric(temp, 'C'),
        status: heatCaution ? 'hot' : 'ok',
      ),
    ];

    if (rainy || tooWindy || tooCalm || heatCaution) {
      recs.add(_recommendation(
        id: 'spray_window_bad',
        moduleId: 'spray_timing',
        moduleTitle: 'Spray Timing',
        title: rainy || tooWindy ? 'Do not spray now' : 'Spray timing is risky',
        decision: rainy
            ? 'Rain can waste spray and move product off target'
            : tooWindy
                ? 'Wind is too strong and drift risk is high'
                : tooCalm
                    ? 'Very calm wind can increase inversion risk'
                    : 'Heat can reduce spray safety and effectiveness',
        urgency: rainy || tooWindy ? DssUrgency.high : DssUrgency.moderate,
        confidence: confidence,
        why:
            'Spray decisions must follow the product label. Weather still gives a strong safety signal before field work.',
        action:
            'Delay spraying until wind is steady, rain is absent, and temperature is safer. Follow the label first.',
        check:
            'Check wind direction, nearby sensitive crops, nozzle setup, and product label restrictions.',
        evidence: evidence,
      ));
    }

    return DssModuleResult(
      id: 'spray_timing',
      title: 'Spray Timing',
      score: _score(100 - penalty),
      status: penalty >= 45 ? 'Do Not Spray' : penalty >= 18 ? 'Caution' : 'Good Window',
      summary: penalty >= 45
          ? 'Current weather is not suitable for spraying.'
          : penalty >= 18
              ? 'Spraying needs caution and label checking.'
              : 'Weather is broadly acceptable for spray planning.',
      recommendations: recs,
    );
  }

  DssModuleResult _pestDisease(DssInput input, DssConfidence confidence) {
    final r = input.reading;
    var penalty = 0;
    final recs = <DssRecommendation>[];
    final temp = r?.temp;
    final rain = r?.rain;
    final moisture = r?.moist;
    final diseaseTemp = temp != null &&
        temp >= input.crop.diseaseTempMinC &&
        temp <= input.crop.diseaseTempMaxC;
    final wet = (rain != null && rain > 0) ||
        (moisture != null && moisture > input.stage.moistureUpper);
    final hotDry = temp != null &&
        temp >= input.crop.tempHotC &&
        moisture != null &&
        moisture < input.stage.moistureLower;

    if (diseaseTemp && wet) penalty += 34;
    if (hotDry) penalty += 20;
    if (input.crop.pestRisk == 'high') penalty += 8;

    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'Disease temp band',
        value:
            '${_fixed(input.crop.diseaseTempMinC)}-${_fixed(input.crop.diseaseTempMaxC)} C',
        status: diseaseTemp ? 'active' : 'outside',
      ),
      DssEvidence(
        label: 'Rain/wet signal',
        value: wet ? 'Present' : 'Not strong',
        status: wet ? 'wet' : 'clear',
      ),
      DssEvidence(
        label: 'Crop pest risk',
        value: input.crop.pestRisk,
        status: input.crop.pestRisk,
      ),
    ];

    if (diseaseTemp && wet) {
      recs.add(_recommendation(
        id: 'disease_scouting',
        moduleId: 'pest_disease',
        moduleTitle: 'Pest & Disease Risk',
        title: 'Scout for disease symptoms',
        decision: 'Warm and wet conditions can favor disease',
        urgency: DssUrgency.moderate,
        confidence:
            confidence == DssConfidence.high ? DssConfidence.medium : confidence,
        why:
            'Disease needs a susceptible crop, a pathogen, and suitable weather. The station is showing a suitable weather signal.',
        action:
            'Walk the field and inspect leaves, stems, flowers, and lower canopy before choosing any treatment.',
        check:
            'Look for spots, mildew, rot, yellowing, lesions, and disease starting in dense or wet areas.',
        evidence: evidence,
      ));
    } else if (hotDry && input.crop.pestRisk != 'low') {
      recs.add(_recommendation(
        id: 'pest_scouting',
        moduleId: 'pest_disease',
        moduleTitle: 'Pest & Disease Risk',
        title: 'Scout for pest pressure',
        decision: 'Hot dry stress can make pest damage worse',
        urgency: DssUrgency.low,
        confidence:
            confidence == DssConfidence.high ? DssConfidence.medium : confidence,
        why:
            'Pest decisions should be based on field scouting and threshold checks, not sensor weather alone.',
        action:
            'Inspect field edges and weak patches. Use IPM checks before any pesticide decision.',
        check:
            'Look under leaves, at new growth, and around field borders for insects or fresh damage.',
        evidence: evidence,
      ));
    }

    return DssModuleResult(
      id: 'pest_disease',
      title: 'Pest & Disease Risk',
      score: _score(100 - penalty),
      status: penalty >= 30 ? 'Scout Today' : penalty >= 15 ? 'Watch' : 'Low Signal',
      summary: penalty >= 30
          ? 'Weather supports scouting for pest or disease risk.'
          : penalty >= 15
              ? 'Some pest or disease risk signals are present.'
              : 'No strong pest or disease weather signal.',
      recommendations: recs,
    );
  }

  DssModuleResult _stageReadiness(DssInput input, DssConfidence confidence) {
    final stageName = input.stage.name.toLowerCase();
    final rain = input.reading?.rain;
    final moisture = input.reading?.moist;
    var penalty = 0;
    final recs = <DssRecommendation>[];

    final nearingHarvest = stageName.contains('maturity') ||
        stageName.contains('harvest') ||
        stageName.contains('grain filling') ||
        stageName.contains('fruit');
    final rainy = rain != null && rain > 0;
    final wetSoil =
        moisture != null && moisture > input.stage.moistureUpper + 8;

    if (nearingHarvest) penalty += 8;
    if (nearingHarvest && (rainy || wetSoil)) penalty += 22;

    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'Stage',
        value: input.stage.name,
        status: input.stage.sensitivity,
      ),
      DssEvidence(
        label: 'Stage note',
        value: input.stage.actionNote,
        status: 'guide',
      ),
    ];

    if (nearingHarvest) {
      recs.add(_recommendation(
        id: 'stage_harvest_planning',
        moduleId: 'stage_readiness',
        moduleTitle: 'Stage / Harvest Readiness',
        title: 'Start field planning for this stage',
        decision: rainy || wetSoil
            ? 'Avoid rushing harvest or field work in wet conditions'
            : 'Prepare the next field operation',
        urgency: rainy || wetSoil ? DssUrgency.moderate : DssUrgency.low,
        confidence: confidence,
        why:
            'The selected crop stage changes which field operation matters most.',
        action:
            'Use the stage note as a checklist and confirm crop maturity directly in the field.',
        check:
            'Check grain, fruit, bulb, or biomass condition based on the selected crop.',
        evidence: evidence,
      ));
    }

    return DssModuleResult(
      id: 'stage_readiness',
      title: 'Stage / Harvest Readiness',
      score: _score(100 - penalty),
      status: nearingHarvest ? 'Plan Work' : 'In Season',
      summary: nearingHarvest
          ? 'The selected stage needs operation planning.'
          : 'No special harvest-stage signal from the selected stage.',
      recommendations: recs,
    );
  }

  DssScore _fieldHealthScore(List<DssModuleResult> modules) {
    final weights = <String, double>{
      'sensor_confidence': 1.2,
      'irrigation_decision': 1.1,
      'crop_stress': 1.4,
      'soil_health': 1.2,
      'nutrients': 0.9,
      'ph_suitability': 0.8,
      'salinity': 1.0,
      'spray_timing': 0.7,
      'pest_disease': 0.8,
      'stage_readiness': 0.4,
    };
    var total = 0.0;
    var weightTotal = 0.0;
    for (final module in modules) {
      final weight = weights[module.id] ?? 1.0;
      total += module.score * weight;
      weightTotal += weight;
    }
    final score = _score(total / weightTotal);
    return DssScore(
      value: score,
      label: score >= 82
          ? 'Field looks stable'
          : score >= 65
              ? 'Needs watching'
              : score >= 45
                  ? 'Action needed'
                  : 'High risk today',
      summary: score >= 82
          ? 'Most DSS modules are inside safe working bands.'
          : score >= 65
              ? 'There are issues to check, but the field is not in severe risk.'
              : score >= 45
                  ? 'Handle the priority actions before routine work.'
                  : 'Field decisions need immediate human checking.',
    );
  }

  DssConfidence _dataConfidence(DssInput input) {
    final reading = input.reading;
    if (reading == null) {
      return DssConfidence.low;
    }
    var missing = 0;
    for (final value in <double?>[
      reading.moist,
      reading.temp,
      reading.ec,
      reading.ph,
      reading.n,
      reading.p,
      reading.k,
      reading.ws,
      reading.rain,
    ]) {
      if (value == null) missing++;
    }
    final staleMinutes =
        (input.irrigationProfile?.staleAfterMinutes ?? 15)
            .clamp(5, 120)
            .toInt();
    final stale =
        DateTime.now().difference(reading.recordedAt).inMinutes > staleMinutes;
    final health =
        input.monitoring?.sensorHealth.values ?? const <SensorHealth>[];
    final hasStaleHealth = health.any((item) => item.freshness == 'stale');
    if (stale || hasStaleHealth || missing >= 5) {
      return DssConfidence.low;
    }
    if (missing >= 2) {
      return DssConfidence.medium;
    }
    return DssConfidence.high;
  }

  DssRecommendation _recommendation({
    required String id,
    required String moduleId,
    required String moduleTitle,
    required String title,
    required String decision,
    required DssUrgency urgency,
    required DssConfidence confidence,
    required String why,
    required String action,
    required String check,
    required List<DssEvidence> evidence,
  }) {
    return DssRecommendation(
      id: id,
      moduleId: moduleId,
      moduleTitle: moduleTitle,
      title: title,
      decision: decision,
      urgency: urgency,
      confidence: confidence,
      whyItMatters: why,
      farmerAction: action,
      fieldCheck: check,
      evidence: evidence,
    );
  }

  int _compareRecommendations(
    DssRecommendation a,
    DssRecommendation b,
  ) {
    final urgency = _urgencyRank(b.urgency).compareTo(_urgencyRank(a.urgency));
    if (urgency != 0) {
      return urgency;
    }
    return _confidenceRank(b.confidence).compareTo(_confidenceRank(a.confidence));
  }

  int _urgencyRank(DssUrgency urgency) {
    switch (urgency) {
      case DssUrgency.critical:
        return 5;
      case DssUrgency.high:
        return 4;
      case DssUrgency.moderate:
        return 3;
      case DssUrgency.low:
        return 2;
      case DssUrgency.info:
        return 1;
    }
  }

  int _confidenceRank(DssConfidence confidence) {
    switch (confidence) {
      case DssConfidence.high:
        return 3;
      case DssConfidence.medium:
        return 2;
      case DssConfidence.low:
        return 1;
    }
  }

  bool _nutrientLow(double? value, String nutrient, String demand) {
    if (value == null) {
      return false;
    }
    final base = switch (nutrient) {
      'n' => 35.0,
      'p' => 18.0,
      'k' => 75.0,
      _ => 25.0,
    };
    final multiplier = switch (demand) {
      'high' => 1.15,
      'low' => 0.85,
      _ => 1.0,
    };
    return value < base * multiplier;
  }

  int _sensitivePenalty(DssCropStage stage, int base) {
    return switch (stage.sensitivity) {
      'high' => (base * 1.25).round(),
      'low' => (base * 0.75).round(),
      _ => base,
    };
  }

  int _demandPenalty(String demand, int base) {
    return switch (demand) {
      'high' => (base * 1.2).round(),
      'low' => (base * 0.75).round(),
      _ => base,
    };
  }

  double? _ecDsM(double? rawEc) {
    if (rawEc == null) {
      return null;
    }
    if (rawEc > 50) {
      return rawEc / 1000.0;
    }
    return rawEc;
  }

  double? _ecTrendDelta(StationTrends? trends) {
    final series = trends?.series['ec'];
    if (series == null || series.length < 2) {
      return null;
    }
    final values = series
        .map((point) => _ecDsM(point.value))
        .whereType<double>()
        .toList(growable: false);
    if (values.length < 2) {
      return null;
    }
    return values.last - values.first;
  }

  double? _trendDelta(StationTrends? trends, String key) {
    final series = trends?.series[key];
    if (series == null || series.length < 2) {
      return null;
    }
    final values = series
        .map((point) => point.value)
        .whereType<double>()
        .toList(growable: false);
    if (values.length < 2) {
      return null;
    }
    return values.last - values.first;
  }

  double? _trendAverage(StationTrends? trends, String key) {
    final series = trends?.series[key];
    if (series == null || series.isEmpty) {
      return null;
    }
    final values = series
        .map((point) => point.value)
        .whereType<double>()
        .toList(growable: false);
    if (values.isEmpty) {
      return null;
    }
    final total = values.fold<double>(0, (sum, value) => sum + value);
    return total / values.length;
  }

  String _metric(double? value, String unit) {
    if (value == null) {
      return 'Missing';
    }
    return unit.isEmpty ? _fixed(value) : '${_fixed(value)} $unit';
  }

  String _fixed(double value) {
    final fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  int _score(num value) {
    return value.clamp(0, 100).round();
  }
}
