class StationSettings {
  const StationSettings({
    required this.deviceId,
    required this.stationName,
    required this.sensors,
    required this.polling,
    required this.updatedAt,
  });

  final String deviceId;
  final String? stationName;
  final StationSensorSettings sensors;
  final StationPollingSettings polling;
  final DateTime? updatedAt;

  factory StationSettings.fromJson(Map<String, dynamic> json) {
    return StationSettings(
      deviceId: json['device_id'] as String,
      stationName: json['station_name'] as String?,
      sensors: StationSensorSettings.fromJson(
          json['sensors'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      polling: StationPollingSettings.fromJson(
          json['polling'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }
}

class StationSensorSettings {
  const StationSensorSettings({
    required this.windSpeedEnabled,
    required this.windDirectionEnabled,
    required this.soilEnabled,
    required this.rainEnabled,
    required this.uvEnabled,
  });

  final bool windSpeedEnabled;
  final bool windDirectionEnabled;
  final bool soilEnabled;
  final bool rainEnabled;
  final bool uvEnabled;

  factory StationSensorSettings.fromJson(Map<String, dynamic> json) {
    bool enabledFor(String key) {
      final raw = json[key];
      if (raw is Map<String, dynamic>) {
        return raw['enabled'] == true;
      }
      return false;
    }

    return StationSensorSettings(
      windSpeedEnabled: enabledFor('wind_speed'),
      windDirectionEnabled: enabledFor('wind_direction'),
      soilEnabled: enabledFor('soil'),
      rainEnabled: enabledFor('rain'),
      uvEnabled: enabledFor('uv'),
    );
  }
}

class StationPollingSettings {
  const StationPollingSettings({
    required this.pollIntervalSeconds,
    required this.interReadDelayMs,
    required this.sensorReadOrder,
    required this.schedule,
  });

  final int pollIntervalSeconds;
  final int interReadDelayMs;
  final List<String> sensorReadOrder;
  final StationScheduleSettings schedule;

  factory StationPollingSettings.fromJson(Map<String, dynamic> json) {
    final rawOrder = json['sensor_read_order'];
    final order = rawOrder is List
        ? rawOrder
            .whereType<String>()
            .map((value) => value.toLowerCase())
            .toList()
        : <String>[];

    return StationPollingSettings(
      pollIntervalSeconds:
          (json['poll_interval_seconds'] as num?)?.toInt() ?? 0,
      interReadDelayMs: (json['inter_read_delay_ms'] as num?)?.toInt() ?? 0,
      sensorReadOrder: order,
      schedule: StationScheduleSettings.fromJson(
          json['schedule'] as Map<String, dynamic>? ?? <String, dynamic>{}),
    );
  }
}

class StationScheduleSettings {
  const StationScheduleSettings({
    required this.enabled,
    required this.mode,
    required this.intervalDays,
    required this.runTimes,
    required this.anchorDate,
    required this.days,
    required this.startTime,
    required this.endTime,
    required this.timezone,
    required this.region,
  });

  final bool enabled;
  final String mode;
  final int intervalDays;
  final List<String> runTimes;
  final DateTime? anchorDate;
  final List<String> days;
  final String startTime;
  final String endTime;
  final String timezone;
  final String region;

  factory StationScheduleSettings.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    final days = rawDays is List
        ? rawDays
            .whereType<String>()
            .map((value) => value.toLowerCase())
            .toList()
        : const <String>[];
    final rawRunTimes = json['run_times'];
    final runTimes = rawRunTimes is List
        ? rawRunTimes
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList()
        : <String>[];

    return StationScheduleSettings(
      enabled: json['enabled'] == true,
      mode: (json['mode'] as String? ?? 'window').toLowerCase(),
      intervalDays: (json['interval_days'] as num?)?.toInt() ?? 1,
      runTimes: runTimes,
      anchorDate: json['anchor_date'] == null
          ? null
          : DateTime.tryParse(json['anchor_date'].toString())?.toLocal(),
      days: days,
      startTime: json['start_time'] as String? ?? '00:00',
      endTime: json['end_time'] as String? ?? '23:59',
      timezone: json['timezone'] as String? ?? 'Asia/Karachi',
      region: json['region'] as String? ?? 'Pakistan',
    );
  }
}

class StationSettingsPatch {
  const StationSettingsPatch({
    this.sensorEnabled,
    this.pollIntervalSeconds,
    this.interReadDelayMs,
    this.sensorReadOrder,
    this.schedule,
  });

  final Map<String, bool>? sensorEnabled;
  final int? pollIntervalSeconds;
  final int? interReadDelayMs;
  final List<String>? sensorReadOrder;
  final StationScheduleSettingsPatch? schedule;

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{};

    if (sensorEnabled != null && sensorEnabled!.isNotEmpty) {
      payload['sensors'] = sensorEnabled!.map(
        (key, value) => MapEntry(key, <String, dynamic>{'enabled': value}),
      );
    }

    final polling = <String, dynamic>{};
    if (pollIntervalSeconds != null) {
      polling['poll_interval_seconds'] = pollIntervalSeconds;
    }
    if (interReadDelayMs != null) {
      polling['inter_read_delay_ms'] = interReadDelayMs;
    }
    if (sensorReadOrder != null && sensorReadOrder!.isNotEmpty) {
      polling['sensor_read_order'] = sensorReadOrder;
    }
    if (schedule != null) {
      polling['schedule'] = schedule!.toJson();
    }
    if (polling.isNotEmpty) {
      payload['polling'] = polling;
    }

    return payload;
  }
}

class StationScheduleSettingsPatch {
  const StationScheduleSettingsPatch({
    this.enabled,
    this.mode,
    this.intervalDays,
    this.runTimes,
    this.anchorDate,
    this.days,
    this.startTime,
    this.endTime,
    this.timezone,
    this.region,
  });

  final bool? enabled;
  final String? mode;
  final int? intervalDays;
  final List<String>? runTimes;
  final DateTime? anchorDate;
  final List<String>? days;
  final String? startTime;
  final String? endTime;
  final String? timezone;
  final String? region;

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{};
    if (enabled != null) {
      payload['enabled'] = enabled;
    }
    if (mode != null) {
      payload['mode'] = mode;
    }
    if (intervalDays != null) {
      payload['interval_days'] = intervalDays;
    }
    if (runTimes != null) {
      payload['run_times'] = runTimes;
    }
    if (anchorDate != null) {
      payload['anchor_date'] = _formatDate(anchorDate!);
    }
    if (days != null) {
      payload['days'] = days;
    }
    if (startTime != null) {
      payload['start_time'] = startTime;
    }
    if (endTime != null) {
      payload['end_time'] = endTime;
    }
    if (timezone != null) {
      payload['timezone'] = timezone;
    }
    if (region != null) {
      payload['region'] = region;
    }
    return payload;
  }
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
