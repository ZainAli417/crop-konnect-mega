import '../models/dss.dart';
import '../models/monitoring_status.dart';
import '../models/station_trends.dart';

// ════════════════════════════════════════════════════════════════════════════
//  DSS Engine
//  Compares live sensors against what the chosen crop needs at its current
//  (auto-computed) growth stage and returns plain, scored field decisions.
//  Tone is firm and human — no jargon, no "low confidence" hedging. Every
//  reading carries a traffic-light tone (good / watch / act) and a one-line
//  hint so the farmer reads colour and words, not raw numbers.
// ════════════════════════════════════════════════════════════════════════════

class DssEngine {
  const DssEngine();

  DssAnalysis analyze(DssInput input) {
    final dataConfidence = _dataConfidence(input);
    final modules = <DssModuleResult>[
      _liveData(input),
      _irrigation(input),
      _cropStress(input),
      _temperature(input),
      _soilHealth(input),
      _nutrients(input),
      _phSuitability(input),
      _salinity(input),
      _sprayTiming(input),
      _pestDisease(input),
      _stageTracker(input),
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
          'Built from your live station readings, checked against what ${input.crop.name} needs during the ${input.stage.name} stage.',
    );
  }

  // ───────────────────────────────────────────────────────────── Live Data ──

  DssModuleResult _liveData(DssInput input) {
    final reading = input.reading;
    var penalty = 0;
    final recs = <DssRecommendation>[];
    final evidence = <DssEvidence>[];

    if (reading == null) {
      penalty += 80;
      evidence.add(const DssEvidence(
        label: 'Latest reading',
        value: 'None',
        status: 'offline',
        tone: DssTone.bad,
        note: 'The station has not sent anything yet',
      ));
      recs.add(_rec(
        id: 'sensor_missing',
        moduleId: 'live_data',
        moduleTitle: 'Live Data',
        title: 'Your station is not sending data',
        decision: 'Get it back online before you act on anything here',
        urgency: DssUrgency.high,
        why:
            'Every tip below comes from fresh field readings. Right now none are coming in.',
        action:
            'Walk to the station and check the power, the network, and the soil sensor cable. Get one reading flowing.',
        check: 'Look for a flat battery, a loose wire, or damage.',
        evidence: evidence,
      ));
    } else {
      final staleMinutes = (input.irrigationProfile?.staleAfterMinutes ?? 15)
          .clamp(5, 120)
          .toInt();
      final age = DateTime.now().difference(reading.recordedAt).inMinutes;
      final fresh = age <= staleMinutes;
      evidence.add(DssEvidence(
        label: 'Last update',
        value: age <= 1 ? 'Just now' : '$age min ago',
        status: fresh ? 'fresh' : 'old',
        tone: fresh ? DssTone.good : DssTone.warn,
        note: fresh ? 'Readings are current' : 'Older than your $staleMinutes-min limit',
      ));
      if (!fresh) {
        penalty += 30;
        recs.add(_rec(
          id: 'sensor_stale',
          moduleId: 'live_data',
          moduleTitle: 'Live Data',
          title: 'Your readings are $age minutes old',
          decision: 'Wake the station so today\'s advice uses today\'s field',
          urgency: DssUrgency.moderate,
          why:
              'The newest reading is older than the $staleMinutes-minute limit you set.',
          action: 'Wake the logger and make sure it is sending before you spend money or labour.',
          check: 'Check the logger clock, the network signal, and that the probe is in the soil.',
          evidence: evidence,
        ));
      }

      final missing = <String>[
        if (reading.moist == null) 'moisture',
        if (reading.temp == null) 'temperature',
        if (reading.ec == null) 'salt (EC)',
        if (reading.ph == null) 'pH',
        if (reading.n == null) 'nitrogen',
        if (reading.p == null) 'phosphorus',
        if (reading.k == null) 'potassium',
        if (reading.ws == null) 'wind',
        if (reading.rain == null) 'rain',
      ];
      penalty += missing.length * 5;
      evidence.add(DssEvidence(
        label: 'Sensors working',
        value: '${9 - missing.length} of 9',
        status: missing.length <= 2 ? 'good' : 'gaps',
        tone: missing.isEmpty
            ? DssTone.good
            : missing.length <= 2
                ? DssTone.good
                : DssTone.warn,
        note: missing.isEmpty ? 'All sensors reporting' : 'Not reporting: ${missing.join(', ')}',
      ));
      if (missing.length >= 4) {
        recs.add(_rec(
          id: 'sensor_gaps',
          moduleId: 'live_data',
          moduleTitle: 'Live Data',
          title: '${missing.length} sensors are quiet',
          decision: 'Bring them back so the advice can see your whole field',
          urgency: DssUrgency.moderate,
          why:
              'These are not reporting: ${missing.join(', ')}. That leaves blind spots in the advice.',
          action: 'Turn these sensors back on, or service them, in the station settings.',
          check: 'Check for switched-off sensors or a recent settings change.',
          evidence: evidence,
        ));
      }
    }

    final score = _score(100 - penalty);
    return DssModuleResult(
      id: 'live_data',
      title: 'Live Data',
      score: score,
      status: penalty <= 15 ? 'Live' : penalty <= 45 ? 'Patchy' : 'Offline',
      summary: penalty <= 15
          ? 'Your station is sending fresh readings. Everything below is up to date.'
          : penalty <= 45
              ? 'Readings are coming in but with gaps. Close them for the clearest picture.'
              : 'The station is too quiet to trust. Fix the connection first.',
      recommendations: recs,
    );
  }

  // ──────────────────────────────────────────────────────────── Irrigation ──

  DssModuleResult _irrigation(DssInput input) {
    final r = input.reading;
    final stage = input.stage;
    var penalty = 0;
    final recs = <DssRecommendation>[];
    final moisture = r?.moist;
    final rain = r?.rain;
    final temp = r?.temp;

    final lowMoisture = moisture != null && moisture < stage.moistureLower;
    final highMoisture = moisture != null && moisture > stage.moistureUpper;
    final rainDetected = rain != null && rain > 0;
    final hot = temp != null && temp >= input.crop.tempHotC;

    if (lowMoisture) penalty += _bySensitivity(stage, 32);
    if (hot && lowMoisture) penalty += 12;
    if (highMoisture || rainDetected) penalty += 8;

    final band = '${_fixed(stage.moistureLower)}–${_fixed(stage.moistureUpper)}%';
    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'Soil moisture',
        value: _metric(moisture, '%'),
        status: lowMoisture ? 'dry' : highMoisture ? 'wet' : 'just right',
        tone: moisture == null
            ? DssTone.info
            : lowMoisture
                ? DssTone.bad
                : highMoisture
                    ? DssTone.warn
                    : DssTone.good,
        note: 'How wet the soil is now',
      ),
      DssEvidence(
        label: 'What ${input.crop.name} wants',
        value: band,
        status: 'target',
        note: 'Keep moisture inside this range at ${stage.name}',
      ),
      DssEvidence(
        label: 'Rain',
        value: _metric(rain, 'mm'),
        status: rainDetected ? 'raining' : 'dry',
        tone: rainDetected ? DssTone.info : DssTone.info,
        note: rainDetected ? 'Rain is falling on the field' : 'No rain right now',
      ),
    ];

    if (lowMoisture && !rainDetected) {
      recs.add(_rec(
        id: 'irrigation_needed',
        moduleId: 'irrigation',
        moduleTitle: 'Irrigation',
        title: hot ? 'Water your ${input.crop.name} today' : 'Time to water',
        decision: 'The soil is drier than ${input.crop.name} needs right now',
        urgency: hot ? DssUrgency.high : DssUrgency.moderate,
        why: hot
            ? 'The soil is below the $band it should sit at, and the heat is drying it out even faster.'
            : 'The soil is below the $band ${input.crop.name} should sit at during ${stage.name}.',
        action: 'Water the field until the soil is back in the $band range. Stop there — do not flood it.',
        check: 'Dig down to the roots and feel the soil. Check the pump or pipe is watering evenly.',
        evidence: evidence,
      ));
    } else if (rainDetected || highMoisture) {
      recs.add(_rec(
        id: 'irrigation_hold',
        moduleId: 'irrigation',
        moduleTitle: 'Irrigation',
        title: 'No watering needed',
        decision: rainDetected
            ? 'Rain is doing the job — extra water is wasted today'
            : 'The soil already has plenty of water',
        urgency: DssUrgency.low,
        why: 'Too much water wastes fuel and can rot roots or bring disease.',
        action: 'Leave the pump off and let the soil dry back toward the right range.',
        check: 'Look for pooling water, blocked drains, or soggy low spots.',
        evidence: evidence,
      ));
    }

    final score = _score(100 - penalty);
    return DssModuleResult(
      id: 'irrigation',
      title: 'Irrigation',
      score: score,
      status: lowMoisture ? 'Water now' : rainDetected || highMoisture ? 'No need' : 'Just right',
      summary: lowMoisture
          ? 'The soil is too dry for ${input.crop.name}. Watering is the top job.'
          : rainDetected || highMoisture
              ? 'There is already enough water in the field. Hold off.'
              : 'The soil has just the right amount of water for ${input.crop.name} now.',
      recommendations: recs,
    );
  }

  // ─────────────────────────────────────────────────────────── Crop Stress ──

  DssModuleResult _cropStress(DssInput input) {
    final r = input.reading;
    final stage = input.stage;
    var penalty = 0;
    final recs = <DssRecommendation>[];

    final moisture = r?.moist;
    final temp = r?.temp;
    final solar = r?.solar;
    final wind = r?.ws;
    final moistureTrend = _trendDelta(input.trends, 'moist');
    final tempAverage = _trendAverage(input.trends, 'temp');

    final lowMoisture = moisture != null && moisture < stage.moistureLower;
    final hot = temp != null && temp >= input.crop.tempHotC;
    final highSolar = solar != null && solar >= 700;
    final dryingWind = wind != null && wind >= 6;
    final moistureFalling = moistureTrend != null && moistureTrend <= -8;
    final sustainedHeat =
        tempAverage != null && tempAverage >= input.crop.tempHotC - 2;

    if (lowMoisture) penalty += _bySensitivity(stage, 26);
    if (hot) penalty += _bySensitivity(stage, 24);
    if (highSolar) penalty += 12;
    if (dryingWind) penalty += 10;
    if (moistureFalling) penalty += 8;
    if (sustainedHeat) penalty += 8;

    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'Soil moisture',
        value: _metric(moisture, '%'),
        status: lowMoisture ? 'dry' : 'fine',
        tone: moisture == null ? DssTone.info : lowMoisture ? DssTone.bad : DssTone.good,
        note: 'Dry soil stresses the crop',
      ),
      DssEvidence(
        label: 'Heat',
        value: _metric(temp, '°C'),
        status: hot ? 'hot' : 'fine',
        tone: temp == null ? DssTone.info : hot ? DssTone.bad : DssTone.good,
        note: 'Above ${_fixed(input.crop.tempHotC)}°C stresses ${input.crop.name}',
      ),
      DssEvidence(
        label: 'Sun strength',
        value: _metric(solar, 'W/m²'),
        status: highSolar ? 'strong' : 'fine',
        tone: solar == null ? DssTone.info : highSolar ? DssTone.warn : DssTone.good,
        note: 'Strong sun dries leaves faster',
      ),
      DssEvidence(
        label: 'Moisture trend (24h)',
        value: moistureTrend == null
            ? '—'
            : '${moistureTrend >= 0 ? '+' : ''}${_fixed(moistureTrend)}%',
        status: moistureFalling ? 'falling' : 'steady',
        tone: moistureTrend == null ? DssTone.info : moistureFalling ? DssTone.warn : DssTone.good,
        note: 'Is the soil drying out over the day',
      ),
    ];

    if (lowMoisture && hot) {
      recs.add(_rec(
        id: 'crop_stress_heat_dry',
        moduleId: 'crop_stress',
        moduleTitle: 'Crop Stress',
        title: 'Your crop is stressed — act today',
        decision: 'It is hot and the soil is dry at the same time, and that cuts your harvest',
        urgency: DssUrgency.high,
        why:
            '${input.crop.name} at ${stage.name} loses yield fast when the soil is dry and the day is hot together.',
        action: 'Water the field to refill the roots and cool the crop. Skip ploughing or any extra strain today.',
        check: 'Look for curled, dull, or drooping leaves at midday, and dry soil down at the roots.',
        evidence: evidence,
      ));
    } else if (lowMoisture || hot || highSolar) {
      recs.add(_rec(
        id: 'crop_stress_watch',
        moduleId: 'crop_stress',
        moduleTitle: 'Crop Stress',
        title: 'Stress is starting to build',
        decision: 'One thing (water, heat, or strong sun) is pushing your crop',
        urgency: lowMoisture || hot ? DssUrgency.moderate : DssUrgency.low,
        why: 'Caught early this is cheap to fix. Left alone it eats into your harvest.',
        action: 'Walk the field before the midday heat and fix the one thing flagged below.',
        check: 'Look for wilting, scorched leaves, weak flowers, or patches doing worse than the rest.',
        evidence: evidence,
      ));
    }

    final score = _score(100 - penalty);
    return DssModuleResult(
      id: 'crop_stress',
      title: 'Crop Stress',
      score: score,
      status: penalty >= 45 ? 'Stressed' : penalty >= 20 ? 'Building' : 'Happy',
      summary: penalty >= 45
          ? 'Your ${input.crop.name} is under real stress. Act today.'
          : penalty >= 20
              ? 'A little stress is building. Fix it before it costs you.'
              : 'Your ${input.crop.name} is comfortable. Nothing is stressing it right now.',
      recommendations: recs,
    );
  }

  // ─────────────────────────────────────────────────────────── Temperature ──

  DssModuleResult _temperature(DssInput input) {
    final stage = input.stage;
    final t = input.reading?.temp;
    var penalty = 0;
    final recs = <DssRecommendation>[];

    final optMin = stage.tempOptMin;
    final optMax = stage.tempOptMax;
    final hot = t != null && t >= input.crop.tempHotC;
    final cold = t != null && t <= input.crop.tempColdC;
    final aboveComfort = t != null && !hot && t > optMax;
    final belowComfort = t != null && !cold && t < optMin;

    if (hot) {
      penalty += _bySensitivity(stage, 30);
    } else if (aboveComfort) {
      penalty += 14;
    }
    if (cold) {
      penalty += _bySensitivity(stage, 26);
    } else if (belowComfort) {
      penalty += 12;
    }
    if (t == null) penalty += 12;

    final inBand = t != null && !hot && !cold && !aboveComfort && !belowComfort;
    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'Temperature now',
        value: _metric(t, '°C'),
        status: hot ? 'too hot' : cold ? 'too cold' : inBand ? 'just right' : 'on the edge',
        tone: t == null
            ? DssTone.info
            : hot || cold
                ? DssTone.bad
                : inBand
                    ? DssTone.good
                    : DssTone.warn,
        note: 'What the field feels right now',
      ),
      DssEvidence(
        label: '${input.crop.name} likes',
        value: '${_fixed(optMin)}–${_fixed(optMax)}°C',
        status: 'target',
        note: 'Best growing temperature at ${stage.name}',
      ),
    ];

    if (hot) {
      recs.add(_rec(
        id: 'temp_hot',
        moduleId: 'temperature',
        moduleTitle: 'Temperature',
        title: 'Too hot for ${input.crop.name}',
        decision: 'It is hotter than ${input.crop.name} can handle well',
        urgency: DssUrgency.high,
        why:
            'Above ${_fixed(input.crop.tempHotC)}°C, ${input.crop.name} stops growing and can drop flowers or grain at ${stage.name}.',
        action: 'Water to cool the crop and keep the soil moist. Do hard work only in the cool morning or evening.',
        check: 'Look for drooping at midday and burnt leaf edges on the sunny side.',
        evidence: evidence,
      ));
    } else if (cold) {
      recs.add(_rec(
        id: 'temp_cold',
        moduleId: 'temperature',
        moduleTitle: 'Temperature',
        title: 'Too cold — growth is slowing',
        decision: 'It is cold enough to stall ${input.crop.name}',
        urgency: DssUrgency.moderate,
        why:
            'Below ${_fixed(input.crop.tempColdC)}°C, ${input.crop.name} barely grows and tender plants can be hurt.',
        action: 'Hold off on watering and feeding until it warms up. Cover young plants if you can.',
        check: 'Look for frost marks, purple leaves, and growth that has stopped.',
        evidence: evidence,
      ));
    } else if (aboveComfort || belowComfort) {
      recs.add(_rec(
        id: 'temp_edge',
        moduleId: 'temperature',
        moduleTitle: 'Temperature',
        title: aboveComfort ? 'Running a bit warm' : 'Running a bit cool',
        decision: aboveComfort ? 'Warmer than the best range for ${stage.name}' : 'Cooler than the best range for ${stage.name}',
        urgency: DssUrgency.low,
        why: '${input.crop.name} grows best between ${_fixed(optMin)} and ${_fixed(optMax)}°C at ${stage.name}.',
        action: 'Keep the soil moisture steady to help the crop cope, and watch how it goes over the next days.',
        check: 'Compare plants in the open with plants in the shade.',
        evidence: evidence,
      ));
    }

    final score = _score(100 - penalty);
    return DssModuleResult(
      id: 'temperature',
      title: 'Temperature',
      score: score,
      status: hot ? 'Too hot' : cold ? 'Too cold' : aboveComfort || belowComfort ? 'On edge' : 'Just right',
      summary: hot
          ? 'It is too hot for ${input.crop.name}. Cool the crop down.'
          : cold
              ? 'It is too cold for ${input.crop.name}. Hold off on inputs.'
              : aboveComfort || belowComfort
                  ? 'The temperature is just outside the best range for ${stage.name}.'
                  : 'The temperature is just right for ${input.crop.name} at this stage.',
      recommendations: recs,
    );
  }

  // ─────────────────────────────────────────────────────────── Soil Health ──

  DssModuleResult _soilHealth(DssInput input) {
    final r = input.reading;
    final stage = input.stage;
    var penalty = 0;
    final recs = <DssRecommendation>[];

    final ph = r?.ph;
    final ec = _ecDsM(r?.ec);
    final temp = r?.temp;
    final moisture = r?.moist;

    final phOut = ph != null &&
        (ph < input.crop.phMin - 0.2 || ph > input.crop.phMax + 0.2);
    final ecHigh = ec != null && ec >= input.crop.ecThresholdDsM;
    final tempHot = temp != null && temp >= input.crop.tempHotC;
    final tooDry = moisture != null && moisture < stage.moistureLower;

    if (phOut) penalty += 22;
    if (ecHigh) penalty += 24;
    if (tempHot) penalty += 14;
    if (tooDry) penalty += 16;

    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'Soil pH',
        value: _metric(ph, ''),
        status: phOut ? 'off' : 'ok',
        tone: ph == null ? DssTone.info : phOut ? DssTone.warn : DssTone.good,
        note: 'Best ${_fixed(input.crop.phMin)}–${_fixed(input.crop.phMax)} for ${input.crop.name}',
      ),
      DssEvidence(
        label: 'Salt (EC)',
        value: ec == null ? '—' : '${_fixed(ec)} dS/m',
        status: ecHigh ? 'high' : 'ok',
        tone: ec == null ? DssTone.info : ecHigh ? DssTone.bad : DssTone.good,
        note: 'Salt in the soil — high salt blocks water',
      ),
      DssEvidence(
        label: 'Soil moisture',
        value: _metric(moisture, '%'),
        status: tooDry ? 'dry' : 'ok',
        tone: moisture == null ? DssTone.info : tooDry ? DssTone.warn : DssTone.good,
        note: 'Roots need moisture to feed',
      ),
    ];

    if (phOut || ecHigh || tooDry) {
      recs.add(_rec(
        id: 'soil_health_attention',
        moduleId: 'soil_health',
        moduleTitle: 'Soil Health',
        title: 'The soil is holding your crop back',
        decision: ecHigh
            ? 'Salt has built up and is blocking water and food'
            : phOut
                ? 'The soil is too sour or too chalky for the roots'
                : 'The soil is too dry for the roots to work',
        urgency: ecHigh || phOut ? DssUrgency.moderate : DssUrgency.low,
        why: 'The roots can only feed the crop when the soil is the right kind, not too salty, and moist enough.',
        action: ecHigh
            ? 'Water with clean (low-salt) water and improve drainage to wash the salt down past the roots.'
            : phOut
                ? 'Plan the right fix for this field — lime if it is too sour, gypsum or sulphur if it is too chalky.'
                : 'Water the field to bring the roots back to life before the crop suffers.',
        check: 'Look for a white salty crust, hard crusty topsoil, poor roots, or dry patches.',
        evidence: evidence,
      ));
    }

    final score = _score(100 - penalty);
    return DssModuleResult(
      id: 'soil_health',
      title: 'Soil Health',
      score: score,
      status: penalty >= 45 ? 'Needs work' : penalty >= 20 ? 'Watch' : 'Healthy',
      summary: penalty >= 45
          ? 'The soil is limiting your crop. Fix it before spending on seed or fertiliser.'
          : penalty >= 20
              ? 'The soil is usable but one thing needs a look.'
              : 'Your soil is in good shape for ${input.crop.name}.',
      recommendations: recs,
    );
  }

  // ────────────────────────────────────────────────────────────── Nutrition ──

  DssModuleResult _nutrients(DssInput input) {
    final r = input.reading;
    final stage = input.stage;
    var penalty = 0;
    final recs = <DssRecommendation>[];

    final nLow = _nutrientLow(r?.n, 'n', stage.nDemand);
    final pLow = _nutrientLow(r?.p, 'p', stage.pDemand);
    final kLow = _nutrientLow(r?.k, 'k', stage.kDemand);
    final ph = r?.ph;
    final phIssue = ph != null && (ph < input.crop.phMin || ph > input.crop.phMax);

    if (nLow) penalty += _byDemand(stage.nDemand, 18);
    if (pLow) penalty += _byDemand(stage.pDemand, 16);
    if (kLow) penalty += _byDemand(stage.kDemand, 16);
    if (phIssue) penalty += 10;

    final short = <String>[
      if (nLow) 'nitrogen',
      if (pLow) 'phosphorus',
      if (kLow) 'potassium',
    ];

    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'Nitrogen (leaf growth)',
        value: _metric(r?.n, ''),
        status: nLow ? 'low' : 'ok',
        tone: r?.n == null ? DssTone.info : nLow ? DssTone.warn : DssTone.good,
        note: 'Feeds green leafy growth',
      ),
      DssEvidence(
        label: 'Phosphorus (roots)',
        value: _metric(r?.p, ''),
        status: pLow ? 'low' : 'ok',
        tone: r?.p == null ? DssTone.info : pLow ? DssTone.warn : DssTone.good,
        note: 'Builds roots and early strength',
      ),
      DssEvidence(
        label: 'Potassium (filling)',
        value: _metric(r?.k, ''),
        status: kLow ? 'low' : 'ok',
        tone: r?.k == null ? DssTone.info : kLow ? DssTone.warn : DssTone.good,
        note: 'Fills grain/fruit and fights stress',
      ),
    ];

    if (short.isNotEmpty) {
      recs.add(_rec(
        id: 'nutrient_low',
        moduleId: 'nutrients',
        moduleTitle: 'Nutrition',
        title: 'Feed your crop — ${short.join(' and ')} ${short.length == 1 ? 'is' : 'are'} low',
        decision: '${input.crop.name} is hungry for ${short.join(' and ')} at this stage',
        urgency: DssUrgency.moderate,
        why:
            'At ${stage.name}, ${input.crop.name} pulls hard on these. The reading shows ${short.join(' and ')} running short.',
        action: 'Top-dress the low nutrient this week so the crop is not starved during ${stage.name}.',
        check: 'Look for pale or yellow leaves, purple tints, thin stems, or slow patchy growth.',
        evidence: evidence,
      ));
    } else if (phIssue) {
      recs.add(_rec(
        id: 'nutrient_ph_lock',
        moduleId: 'nutrients',
        moduleTitle: 'Nutrition',
        title: 'Food is there but the soil is locking it',
        decision: 'Nutrients look fine, but the soil pH stops the roots taking them',
        urgency: DssUrgency.low,
        why: 'When pH is off the ${_fixed(input.crop.phMin)}–${_fixed(input.crop.phMax)} range, roots cannot take up the food in the soil.',
        action: 'Fix the soil pH first — the food already in the ground becomes usable again.',
        check: 'Compare leaf colour where the crop looks healthy against the pale patches.',
        evidence: evidence,
      ));
    }

    final score = _score(100 - penalty);
    return DssModuleResult(
      id: 'nutrients',
      title: 'Nutrition',
      score: score,
      status: penalty >= 40 ? 'Feed now' : penalty >= 18 ? 'Watch' : 'Well fed',
      summary: penalty >= 40
          ? 'Your crop is short on food it needs at ${stage.name}. Feed it this week.'
          : penalty >= 18
              ? 'One nutrient is running a little low for ${stage.name}.'
              : '${input.crop.name} is getting the food it needs at ${stage.name}.',
      recommendations: recs,
    );
  }

  // ─────────────────────────────────────────────────────────────────── pH ──

  DssModuleResult _phSuitability(DssInput input) {
    final ph = input.reading?.ph;
    var penalty = 0;
    final recs = <DssRecommendation>[];
    final low = ph != null && ph < input.crop.phMin;
    final high = ph != null && ph > input.crop.phMax;
    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'Soil pH',
        value: _metric(ph, ''),
        status: low ? 'sour' : high ? 'chalky' : 'ok',
        tone: ph == null ? DssTone.info : (low || high) ? DssTone.warn : DssTone.good,
        note: 'Under 7 is sour, over 7 is chalky',
      ),
      DssEvidence(
        label: '${input.crop.name} likes',
        value: '${_fixed(input.crop.phMin)}–${_fixed(input.crop.phMax)}',
        status: 'target',
        note: 'Best soil pH for this crop',
      ),
    ];

    if (ph == null) {
      penalty += 12;
    } else if (low || high) {
      penalty += 34;
      recs.add(_rec(
        id: 'ph_outside_crop_range',
        moduleId: 'ph',
        moduleTitle: 'Soil pH',
        title: low ? 'Soil is too sour for ${input.crop.name}' : 'Soil is too chalky for ${input.crop.name}',
        decision: 'The pH is outside the ${_fixed(input.crop.phMin)}–${_fixed(input.crop.phMax)} range it likes',
        urgency: DssUrgency.moderate,
        why:
            '${input.crop.name} feeds best between pH ${_fixed(input.crop.phMin)} and ${_fixed(input.crop.phMax)}. Outside that, food in the soil gets locked away.',
        action: low
            ? 'Add farm lime to bring the pH up into range before the next feed.'
            : 'Add gypsum or sulphur to bring the pH down into range.',
        check: 'Check if the weak growth is across the whole field or just in patches.',
        evidence: evidence,
      ));
    }

    final score = _score(100 - penalty);
    return DssModuleResult(
      id: 'ph',
      title: 'Soil pH',
      score: score,
      status: penalty >= 30 ? 'Off range' : penalty > 0 ? 'No reading' : 'On range',
      summary: penalty >= 30
          ? 'The soil pH is off the range ${input.crop.name} likes and is locking up food.'
          : penalty > 0
              ? 'No pH reading right now. Turn the pH sensor back on to track this.'
              : 'The soil pH is right for ${input.crop.name}.',
      recommendations: recs,
    );
  }

  // ───────────────────────────────────────────────────────────── Salt / EC ──

  DssModuleResult _salinity(DssInput input) {
    final ec = _ecDsM(input.reading?.ec);
    final ecTrend = _ecTrendDelta(input.trends);
    var penalty = 0;
    final recs = <DssRecommendation>[];

    final caution = ec != null && ec >= input.crop.ecThresholdDsM * 0.8;
    final high = ec != null && ec >= input.crop.ecThresholdDsM;
    final rising = ecTrend != null && ecTrend >= 0.5;

    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'Salt level (EC)',
        value: ec == null ? '—' : '${_fixed(ec)} dS/m',
        status: high ? 'high' : caution ? 'climbing' : 'safe',
        tone: ec == null ? DssTone.info : high ? DssTone.bad : caution ? DssTone.warn : DssTone.good,
        note: 'How salty the soil water is',
      ),
      DssEvidence(
        label: '${input.crop.name} limit',
        value: '${_fixed(input.crop.ecThresholdDsM)} dS/m',
        status: 'target',
        note: 'Salt above this starts to hurt the crop',
      ),
      DssEvidence(
        label: 'Salt trend (24h)',
        value: ecTrend == null ? '—' : '${ecTrend >= 0 ? '+' : ''}${_fixed(ecTrend)} dS/m',
        status: rising ? 'rising' : 'steady',
        tone: ecTrend == null ? DssTone.info : rising ? DssTone.warn : DssTone.good,
        note: 'Is salt building up over the day',
      ),
    ];

    if (high) {
      penalty += 48;
    } else if (caution) {
      penalty += 24;
    } else if (rising) {
      penalty += 12;
    } else if (ec == null) {
      penalty += 10;
    }

    if (high || caution || rising) {
      recs.add(_rec(
        id: high ? 'salinity_high' : caution ? 'salinity_caution' : 'salinity_rising',
        moduleId: 'salinity',
        moduleTitle: 'Salt / EC',
        title: high ? 'Too much salt for ${input.crop.name}' : 'Salt is creeping up',
        decision: high ? 'Wash the salt out of the root zone now' : 'Get ahead of the salt before it hurts the crop',
        urgency: high ? DssUrgency.high : caution ? DssUrgency.moderate : DssUrgency.low,
        why: 'When the soil is salty, roots struggle to pull in water — so the crop looks thirsty even on wet soil.',
        action: 'Water with clean (low-salt) water to flush the salt down, and improve drainage. Stop salty fertilisers for now.',
        check: 'Look for a white crust on the soil, burnt leaf edges, stunted patches, and poor sprouting.',
        evidence: evidence,
      ));
    }

    final score = _score(100 - penalty);
    return DssModuleResult(
      id: 'salinity',
      title: 'Salt / EC',
      score: score,
      status: high ? 'Too salty' : caution || rising ? 'Climbing' : 'Safe',
      summary: high
          ? 'The soil is too salty for ${input.crop.name}. Flush it with clean water.'
          : caution
              ? 'Salt is near the limit for ${input.crop.name}. Act before it crosses.'
              : rising
                  ? 'Salt is slowly building up. Keep it in check.'
                  : 'Salt levels are safe for ${input.crop.name}.',
      recommendations: recs,
    );
  }

  // ─────────────────────────────────────────────────────────── Spray Window ──

  DssModuleResult _sprayTiming(DssInput input) {
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
        value: windMph == null ? '—' : '${_fixed(windMph)} mph',
        status: tooWindy ? 'too strong' : tooCalm ? 'too still' : 'good',
        tone: windMph == null ? DssTone.info : (tooWindy || tooCalm) ? DssTone.warn : DssTone.good,
        note: 'Best between a light 3 and 10 mph',
      ),
      DssEvidence(
        label: 'Rain',
        value: _metric(rain, 'mm'),
        status: rainy ? 'raining' : 'dry',
        tone: rainy ? DssTone.bad : DssTone.good,
        note: 'Rain washes spray off the leaves',
      ),
      DssEvidence(
        label: 'Heat',
        value: _metric(temp, '°C'),
        status: heatCaution ? 'hot' : 'ok',
        tone: temp == null ? DssTone.info : heatCaution ? DssTone.warn : DssTone.good,
        note: 'Heat over 32°C dries spray too fast',
      ),
    ];

    if (rainy || tooWindy || tooCalm || heatCaution) {
      recs.add(_rec(
        id: 'spray_window_bad',
        moduleId: 'spray',
        moduleTitle: 'Spray Window',
        title: rainy || tooWindy ? 'Do not spray now' : 'Wait for a better moment to spray',
        decision: rainy
            ? 'Rain will wash the spray off and waste it'
            : tooWindy
                ? 'The wind will blow the spray off your field'
                : tooCalm
                    ? 'The air is too still — spray can hang and drift later'
                    : 'The heat will dry the spray before it works',
        urgency: rainy || tooWindy ? DssUrgency.high : DssUrgency.moderate,
        why: 'The weather decides whether spray lands where you want it. Right now it will not. Always follow the product label too.',
        action: 'Wait until there is a light steady breeze, the leaves are dry, and it has cooled down.',
        check: 'Check the wind direction, nearby crops, your nozzles, and the label.',
        evidence: evidence,
      ));
    }

    final score = _score(100 - penalty);
    return DssModuleResult(
      id: 'spray',
      title: 'Spray Window',
      score: score,
      status: penalty >= 45 ? 'Do not spray' : penalty >= 18 ? 'Risky' : 'Good to spray',
      summary: penalty >= 45
          ? 'The weather is wrong for spraying. Wait for a better window.'
          : penalty >= 18
              ? 'Spraying is risky right now. Time it well and follow the label.'
              : 'The weather is good for spraying. Follow the product label.',
      recommendations: recs,
    );
  }

  // ─────────────────────────────────────────────────────────── Pest/Disease ──

  DssModuleResult _pestDisease(DssInput input) {
    final r = input.reading;
    final stage = input.stage;
    var penalty = 0;
    final recs = <DssRecommendation>[];
    final temp = r?.temp;
    final rain = r?.rain;
    final moisture = r?.moist;
    final diseaseTemp = temp != null &&
        temp >= input.crop.diseaseTempMinC &&
        temp <= input.crop.diseaseTempMaxC;
    final wet = (rain != null && rain > 0) ||
        (moisture != null && moisture > stage.moistureUpper);
    final hotDry = temp != null &&
        temp >= input.crop.tempHotC &&
        moisture != null &&
        moisture < stage.moistureLower;

    if (diseaseTemp && wet) penalty += 34;
    if (hotDry) penalty += 18;
    if (input.crop.pestRisk == 'high') penalty += 8;

    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'Disease weather',
        value: diseaseTemp && wet ? 'Right for disease' : 'Not right',
        status: diseaseTemp && wet ? 'active' : 'clear',
        tone: diseaseTemp && wet ? DssTone.warn : DssTone.good,
        note: 'Warm and wet together lets disease spread',
      ),
      DssEvidence(
        label: 'Leaf wetness',
        value: wet ? 'Wet' : 'Dry',
        status: wet ? 'wet' : 'dry',
        tone: wet ? DssTone.warn : DssTone.good,
        note: 'Wet leaves help disease take hold',
      ),
    ];

    if (diseaseTemp && wet) {
      recs.add(_rec(
        id: 'disease_scouting',
        moduleId: 'pest_disease',
        moduleTitle: 'Pests & Disease',
        title: 'Check your crop for disease today',
        decision: 'Warm, wet weather is just what disease needs to spread',
        urgency: DssUrgency.moderate,
        why: 'The weather right now is the kind that lets disease start and spread in ${input.crop.name}.',
        action: 'Walk the field and look closely at leaves, stems, and the lower plants before it spreads. Treat early if you find it.',
        check: 'Look for spots, white mould, rot, and disease starting in the thick, damp parts of the field.',
        evidence: evidence,
      ));
    } else if (hotDry && input.crop.pestRisk != 'low') {
      recs.add(_rec(
        id: 'pest_scouting',
        moduleId: 'pest_disease',
        moduleTitle: 'Pests & Disease',
        title: 'Watch for pests on the dry, stressed crop',
        decision: 'Hot dry stress makes pest damage worse',
        urgency: DssUrgency.low,
        why: 'A stressed ${input.crop.name} takes more pest damage. What you see in the field decides whether to treat, not the weather alone.',
        action: 'Check the field edges and the weakest patches, and act on what you actually find.',
        check: 'Look under leaves, on new growth, and along the borders for insects or fresh chew marks.',
        evidence: evidence,
      ));
    }

    final score = _score(100 - penalty);
    return DssModuleResult(
      id: 'pest_disease',
      title: 'Pests & Disease',
      score: score,
      status: penalty >= 30 ? 'Check today' : penalty >= 15 ? 'Watch' : 'Low risk',
      summary: penalty >= 30
          ? 'The weather is right for disease. Check your ${input.crop.name} today.'
          : penalty >= 15
              ? 'Some pest or disease pressure is possible. Keep an eye out.'
              : 'Nothing in the weather is inviting pests or disease right now.',
      recommendations: recs,
    );
  }

  // ─────────────────────────────────────────────────────── Stage & Harvest ──

  DssModuleResult _stageTracker(DssInput input) {
    final stage = input.stage;
    final das = input.daysAfterSowing;
    final cycle = input.cycleDays;
    final recs = <DssRecommendation>[];
    var penalty = 0;

    final rain = input.reading?.rain;
    final moisture = input.reading?.moist;
    final lowerName = stage.name.toLowerCase();
    final nearingHarvest = lowerName.contains('matur') ||
        lowerName.contains('harvest') ||
        lowerName.contains('filling') ||
        lowerName.contains('boll');
    final rainy = rain != null && rain > 0;
    final wetSoil = moisture != null && moisture > stage.moistureUpper + 8;

    if (nearingHarvest && (rainy || wetSoil)) penalty += 18;

    final daysLeftInStage =
        (das != null && stage.endDay > 0) ? (stage.endDay - das).clamp(0, 100000) : null;
    final daysToHarvest =
        (das != null && cycle != null) ? (cycle - das).clamp(0, 100000) : null;

    final evidence = <DssEvidence>[
      DssEvidence(
        label: 'Where you are',
        value: das == null ? stage.name : 'Day $das${cycle != null ? ' of $cycle' : ''}',
        status: 'stage',
        note: 'Days since you sowed',
      ),
      if (daysLeftInStage != null)
        DssEvidence(
          label: 'Left in this stage',
          value: daysLeftInStage == 0 ? 'Changing now' : '$daysLeftInStage days',
          status: 'stage',
          note: 'Then it moves to the next stage',
        ),
      if (daysToHarvest != null)
        DssEvidence(
          label: 'To harvest',
          value: input.pastHarvest ? 'Ready now' : 'about $daysToHarvest days',
          status: input.pastHarvest ? 'due' : 'plan',
          tone: input.pastHarvest ? DssTone.warn : DssTone.info,
          note: 'Roughly, from your sowing date',
        ),
    ];

    if (input.pastHarvest) {
      recs.add(_rec(
        id: 'stage_harvest_due',
        moduleId: 'stage',
        moduleTitle: 'Stage & Harvest',
        title: 'Your ${input.crop.name} is ready to harvest',
        decision: 'The crop has reached the end of its growing time',
        urgency: DssUrgency.moderate,
        why: 'You are past the usual ${cycle ?? 0}-day growing time for ${input.crop.name}.',
        action: 'Check the crop in the field and harvest on the next dry day.',
        check: 'Check the grain, pods, fruit, or roots to be sure they are ready.',
        evidence: evidence,
      ));
    } else if (nearingHarvest) {
      recs.add(_rec(
        id: 'stage_harvest_planning',
        moduleId: 'stage',
        moduleTitle: 'Stage & Harvest',
        title: 'Get ready for harvest',
        decision: rainy || wetSoil
            ? 'Hold heavy work while the ground is wet'
            : 'Line up your equipment and helpers for the final stretch',
        urgency: rainy || wetSoil ? DssUrgency.moderate : DssUrgency.low,
        why:
            '${input.crop.name} is in ${stage.name}${daysToHarvest != null ? ', about $daysToHarvest days from harvest' : ''}. Timing now decides the quality.',
        action: 'Use the focus note above as your checklist and confirm ripeness in the field.',
        check: 'Check the grain, fruit, bulb, or biomass for your crop.',
        evidence: evidence,
      ));
    }

    final score = _score(100 - penalty);
    return DssModuleResult(
      id: 'stage',
      title: 'Stage & Harvest',
      score: score,
      status: input.pastHarvest ? 'Harvest' : nearingHarvest ? 'Final stretch' : 'Growing',
      summary: stage.actionNote,
      recommendations: recs,
    );
  }

  // ─────────────────────────────────────────────────────────────── Scoring ──

  DssScore _fieldHealthScore(List<DssModuleResult> modules) {
    final weights = <String, double>{
      'live_data': 1.0,
      'irrigation': 1.3,
      'crop_stress': 1.4,
      'temperature': 1.1,
      'soil_health': 1.1,
      'nutrients': 1.0,
      'ph': 0.7,
      'salinity': 1.0,
      'spray': 0.6,
      'pest_disease': 0.8,
      'stage': 0.5,
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
      label: score >= 78
          ? 'Your field is on track'
          : score >= 55
              ? 'A few things to handle'
              : 'Needs you today',
      summary: score >= 78
          ? 'Most things are just right for your crop and stage. Keep it up.'
          : score >= 55
              ? 'Your field is in decent shape — clear the jobs below to keep it that way.'
              : 'Some things need fixing today. Start with the jobs at the top.',
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
    final staleMinutes = (input.irrigationProfile?.staleAfterMinutes ?? 15)
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

  DssRecommendation _rec({
    required String id,
    required String moduleId,
    required String moduleTitle,
    required String title,
    required String decision,
    required DssUrgency urgency,
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
      confidence: DssConfidence.high,
      whyItMatters: why,
      farmerAction: action,
      fieldCheck: check,
      evidence: evidence,
    );
  }

  int _compareRecommendations(DssRecommendation a, DssRecommendation b) {
    return _urgencyRank(b.urgency).compareTo(_urgencyRank(a.urgency));
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

  int _bySensitivity(DssCropStage stage, int base) {
    return switch (stage.sensitivity) {
      'high' => (base * 1.25).round(),
      'low' => (base * 0.75).round(),
      _ => base,
    };
  }

  int _byDemand(String demand, int base) {
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
      return '—';
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
