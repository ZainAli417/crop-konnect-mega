List<String> _normalizeSensorReadOrder(Iterable<String> values) {
  final order = <String>[];

  void add(String key) {
    if (key.isNotEmpty && !order.contains(key)) {
      order.add(key);
    }
  }

  for (final value in values) {
    final key = value.trim().toLowerCase();
    if (key == 'wind' || key == 'wind_sensor') {
      add('wind_speed');
      add('wind_direction');
    } else if (key == 'solar') {
      add('uv');
    } else {
      add(key);
    }
  }

  return order;
}

const int kDefaultSensorIntervalSeconds = 3600;

const Map<String, int> kDefaultSensorIntervals = <String, int>{
  'wind': kDefaultSensorIntervalSeconds,
  'soil': kDefaultSensorIntervalSeconds,
  'rain': kDefaultSensorIntervalSeconds,
  'uv': kDefaultSensorIntervalSeconds,
};

String _normalizeSensorIntervalKey(String value) {
  final key = value.trim().toLowerCase();
  if (key == 'wind' ||
      key == 'wind_sensor' ||
      key == 'wind_speed' ||
      key == 'wind_direction') {
    return 'wind';
  }
  return key == 'solar' ? 'uv' : key;
}

int _readsPerDayFromIntervalSeconds(int intervalSeconds) {
  final safeInterval = intervalSeconds < 1 ? 1 : intervalSeconds;
  final reads = (86400 / safeInterval).round();
  return reads < 1 ? 1 : reads;
}

int? _intervalSecondsFromCadence(Map<String, dynamic> value) {
  final intervalSeconds = (value['interval_seconds'] as num?)?.toInt();
  if (intervalSeconds != null && intervalSeconds > 0) {
    return intervalSeconds;
  }
  final readsPerDay = (value['reads_per_day'] as num?)?.toInt();
  if (readsPerDay != null && readsPerDay > 0) {
    return (86400 / readsPerDay).round();
  }
  return null;
}

Map<String, SensorIntervalSettings> _parseSensorIntervals(
  Map<String, dynamic>? json,
) {
  final intervals = <String, SensorIntervalSettings>{
    for (final entry in kDefaultSensorIntervals.entries)
      entry.key: SensorIntervalSettings(
        enabled: false,
        intervalSeconds: entry.value,
      ),
  };
  final rawItems = json?['items'];
  if (rawItems is Map) {
    rawItems.forEach((rawKey, rawValue) {
      if (rawValue is! Map) return;
      final key = _normalizeSensorIntervalKey(rawKey.toString());
      if (!intervals.containsKey(key)) return;
      final value = Map<String, dynamic>.from(rawValue);
      intervals[key] = SensorIntervalSettings(
        enabled: value['enabled'] == true,
        intervalSeconds:
            _intervalSecondsFromCadence(value) ?? kDefaultSensorIntervalSeconds,
      );
    });
  }
  return intervals;
}

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

  bool get windEnabled => windSpeedEnabled || windDirectionEnabled;

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
    required this.sensorIntervals,
  });

  final int pollIntervalSeconds;
  final int interReadDelayMs;
  final List<String> sensorReadOrder;
  final Map<String, SensorIntervalSettings> sensorIntervals;

  factory StationPollingSettings.fromJson(Map<String, dynamic> json) {
    final rawOrder = json['sensor_read_order'];
    final order = rawOrder is List
        ? _normalizeSensorReadOrder(rawOrder.whereType<String>())
        : <String>[];

    return StationPollingSettings(
      pollIntervalSeconds:
          (json['poll_interval_seconds'] as num?)?.toInt() ?? 0,
      interReadDelayMs: (json['inter_read_delay_ms'] as num?)?.toInt() ?? 0,
      sensorReadOrder: order,
      sensorIntervals: _parseSensorIntervals(
          json['sensor_schedule'] as Map<String, dynamic>?),
    );
  }
}

class SensorIntervalSettings {
  const SensorIntervalSettings({
    required this.enabled,
    required this.intervalSeconds,
  });

  final bool enabled;
  final int intervalSeconds;
}

class StationSettingsPatch {
  const StationSettingsPatch({
    this.sensorEnabled,
    this.pollIntervalSeconds,
    this.interReadDelayMs,
    this.sensorReadOrder,
    this.sensorIntervals,
  });

  final Map<String, bool>? sensorEnabled;
  final int? pollIntervalSeconds;
  final int? interReadDelayMs;
  final List<String>? sensorReadOrder;
  final Map<String, int>? sensorIntervals;

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{};

    if (sensorEnabled != null && sensorEnabled!.isNotEmpty) {
      final sensors = sensorEnabled!.map(
        (key, value) => MapEntry(key, <String, dynamic>{'enabled': value}),
      );
      if (sensors.containsKey('wind')) {
        final enabled = sensorEnabled!['wind'] ?? false;
        sensors
          ..remove('wind')
          ..['wind_speed'] = <String, dynamic>{'enabled': enabled}
          ..['wind_direction'] = <String, dynamic>{'enabled': enabled};
      }
      payload['sensors'] = sensors;
    }

    final polling = <String, dynamic>{};
    if (pollIntervalSeconds != null) {
      polling['poll_interval_seconds'] = pollIntervalSeconds;
    }
    if (interReadDelayMs != null) {
      polling['inter_read_delay_ms'] = interReadDelayMs;
    }
    if (sensorReadOrder != null && sensorReadOrder!.isNotEmpty) {
      polling['sensor_read_order'] =
          _normalizeSensorReadOrder(sensorReadOrder!);
    }
    if (sensorIntervals != null && sensorIntervals!.isNotEmpty) {
      final items = <String, dynamic>{};
      sensorIntervals!.forEach((key, intervalSeconds) {
        final normalized = _normalizeSensorIntervalKey(key);
        items[normalized] = <String, dynamic>{
          'mode': 'reads_per_day',
          'reads_per_day': _readsPerDayFromIntervalSeconds(intervalSeconds),
        };
      });
      polling['sensor_schedule'] = <String, dynamic>{'items': items};
    }
    if (polling.isNotEmpty) {
      payload['polling'] = polling;
    }

    return payload;
  }
}
