import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_config.dart';
import '../config/dashboard_theme.dart';
import '../models/station_settings.dart';
import '../viewmodels/station_dashboard_controller.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────

class _T {
  _T._();

  static const double kCardRadius = 16;
  static const double kInnerRadius = 10;
  static const double kPad = 14;
  static const double kGap = 10;
  static const double kColBreak = 740;

  // Neutral palette
  static const Color kCard = Colors.white;
  static const Color kBorder = Color(0xFFE8EDF2);
  static const Color kDivider = Color(0xFFF0F3F7);
  static const Color kChipBg = Color(0xFFF3F6FA);
  static const Color kMuted = Color(0xFF8899AA);
  static const Color kText = Color(0xFF0D1821);
  static const Color kSub = Color(0xFF5A6B7C);

  static BoxDecoration card() => BoxDecoration(
    color: kCard,
    borderRadius: BorderRadius.circular(kCardRadius),
    border: Border.all(color: kBorder, width: 1),
  );

  static TextStyle micro({
    double size = 9,
    Color color = kMuted,
    double spacing = 0.9,
    FontWeight weight = FontWeight.w700,
  }) =>
      GoogleFonts.plusJakartaSans(
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: spacing);

  static TextStyle body({
    double size = 13,
    Color color = kText,
    FontWeight weight = FontWeight.w700,
  }) =>
      GoogleFonts.plusJakartaSans(
          fontSize: size, fontWeight: weight, color: color);

  static TextStyle heading({
    double size = 20,
    FontWeight weight = FontWeight.w800,
    double spacing = -0.4,
  }) =>
      GoogleFonts.plusJakartaSans(
          fontSize: size,
          fontWeight: weight,
          color: kText,
          letterSpacing: spacing);
}

// ─── Constants ────────────────────────────────────────────────────────────────

const List<_RegionOption> _regionOptions = [
  _RegionOption(label: 'Pakistan', timezone: 'Asia/Karachi'),
  _RegionOption(label: 'India', timezone: 'Asia/Kolkata'),
  _RegionOption(label: 'UAE', timezone: 'Asia/Dubai'),
  _RegionOption(label: 'Saudi Arabia', timezone: 'Asia/Riyadh'),
  _RegionOption(label: 'UK', timezone: 'Europe/London'),
  _RegionOption(label: 'US Eastern', timezone: 'America/New_York'),
  _RegionOption(label: 'US Central', timezone: 'America/Chicago'),
  _RegionOption(label: 'US Pacific', timezone: 'America/Los_Angeles'),
];

const Map<String, String> _dayLabels = {
  'mon': 'M',
  'tue': 'T',
  'wed': 'W',
  'thu': 'T',
  'fri': 'F',
  'sat': 'S',
  'sun': 'S',
};

// ─── Settings Tab ─────────────────────────────────────────────────────────────

class SettingsTab extends StatefulWidget {
  const SettingsTab({
    super.key,
    required this.controller,
    required this.mode,
    required this.onModeChanged,
  });

  final StationDashboardController controller;
  final AppDataMode mode;
  final ValueChanged<AppDataMode> onModeChanged;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  int? _pollIntervalSeconds;
  double? _interReadDelay;
  bool? _scheduleEnabled;
  Set<String>? _selectedDays;
  String? _startTime;
  String? _endTime;
  String? _timezone;
  String? _region;

  @override
  void initState() {
    super.initState();
    widget.controller.refreshSettings();
    _seedFromSettings(widget.controller.stationSettings);
  }

  void _seedFromSettings(StationSettings? s) {
    if (s == null) return;
    _pollIntervalSeconds ??= s.polling.pollIntervalSeconds;
    _interReadDelay ??= s.polling.interReadDelayMs.toDouble();
    _scheduleEnabled ??= s.polling.schedule.enabled;
    _selectedDays ??= s.polling.schedule.days.toSet();
    _startTime ??= s.polling.schedule.startTime;
    _endTime ??= s.polling.schedule.endTime;
    _timezone ??= s.polling.schedule.timezone;
    _region ??= s.polling.schedule.region;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final settings = widget.controller.stationSettings;
        final busy = widget.controller.isApplyingSettings;
        _seedFromSettings(settings);

        return RefreshIndicator(
          onRefresh: widget.controller.refreshSettings,
          color: AppTokens.primary,
          backgroundColor: Colors.white,
          displacement: 20,
          child: ListView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              // ── Page header ──
              _PageHeader(),
              const SizedBox(height: 14),

              // ── Data Environment ──
              _SectionLabel(
                  title: 'Data Environment', sub: 'Active telemetry source'),
              const SizedBox(height: 8),
              _ModeSwitcher(
                  mode: widget.mode, onSelected: widget.onModeChanged),

              if (settings == null) ...[
                const SizedBox(height: 32),
                const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTokens.primary)),
              ] else ...[
                const SizedBox(height: _T.kPad),

                // ── Responsive body ──
                LayoutBuilder(builder: (ctx, constraints) {
                  final wide = constraints.maxWidth >= _T.kColBreak;
                  return wide
                      ? _WideLayout(
                    settings: settings,
                    busy: busy,
                    controller: widget.controller,
                    pollIntervalSeconds: _pollIntervalSeconds!,
                    interReadDelay: _interReadDelay!,
                    scheduleEnabled: _scheduleEnabled!,
                    selectedDays: _selectedDays!,
                    startTime: _startTime!,
                    endTime: _endTime!,
                    timezone: _timezone!,
                    region: _region!,
                    onIntervalChanged: (v) {
                      setState(() => _pollIntervalSeconds = v);
                      widget.controller
                          .updatePolling(pollIntervalSeconds: v);
                    },
                    onDelayChanged: (v) =>
                        setState(() => _interReadDelay = v),
                    onDelayEnd: (v) => widget.controller.updatePolling(
                        interReadDelayMs: v.round()),
                    onToggleSensor: (k, val) =>
                        widget.controller.setSensorEnabled(k, val),
                    onEnabled: _onScheduleEnabled,
                    onDayToggle: _toggleDay,
                    onTimePick: _pickScheduleTime,
                    onRegionSelect: _selectRegion,
                    onModeChanged: (m) => widget.controller
                        .updateSchedule(
                        StationScheduleSettingsPatch(mode: m)),
                    onIntervalDaysChanged: (d) =>
                        widget.controller.updateSchedule(
                            StationScheduleSettingsPatch(intervalDays: d)),
                  )
                      : _NarrowLayout(
                    settings: settings,
                    busy: busy,
                    controller: widget.controller,
                    pollIntervalSeconds: _pollIntervalSeconds!,
                    interReadDelay: _interReadDelay!,
                    scheduleEnabled: _scheduleEnabled!,
                    selectedDays: _selectedDays!,
                    startTime: _startTime!,
                    endTime: _endTime!,
                    timezone: _timezone!,
                    region: _region!,
                    onIntervalChanged: (v) {
                      setState(() => _pollIntervalSeconds = v);
                      widget.controller
                          .updatePolling(pollIntervalSeconds: v);
                    },
                    onDelayChanged: (v) =>
                        setState(() => _interReadDelay = v),
                    onDelayEnd: (v) => widget.controller.updatePolling(
                        interReadDelayMs: v.round()),
                    onToggleSensor: (k, val) =>
                        widget.controller.setSensorEnabled(k, val),
                    onEnabled: _onScheduleEnabled,
                    onDayToggle: _toggleDay,
                    onTimePick: _pickScheduleTime,
                    onRegionSelect: _selectRegion,
                    onModeChanged: (m) => widget.controller
                        .updateSchedule(
                        StationScheduleSettingsPatch(mode: m)),
                    onIntervalDaysChanged: (d) =>
                        widget.controller.updateSchedule(
                            StationScheduleSettingsPatch(intervalDays: d)),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }

  void _onScheduleEnabled(bool v) {
    setState(() => _scheduleEnabled = v);
    widget.controller
        .updateSchedule(StationScheduleSettingsPatch(enabled: v));
  }

  Future<void> _toggleDay(String day) async {
    final keys = _dayLabels.keys.toList();
    final days = Set<String>.from(_selectedDays ?? keys);
    days.contains(day) ? days.remove(day) : days.add(day);
    if (days.isEmpty) return;
    final ordered = keys.where(days.contains).toList();
    setState(() => _selectedDays = ordered.toSet());
    await widget.controller
        .updateSchedule(StationScheduleSettingsPatch(days: ordered));
  }

  Future<void> _pickScheduleTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTime(isStart ? _startTime : _endTime),
    );
    if (picked == null) return;
    final fmt =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() => isStart ? _startTime = fmt : _endTime = fmt);
    await widget.controller.updateSchedule(StationScheduleSettingsPatch(
      startTime: isStart ? fmt : null,
      endTime: isStart ? null : fmt,
    ));
  }

  Future<void> _selectRegion(String tz) async {
    final opt = _regionOptions.firstWhere((o) => o.timezone == tz,
        orElse: () => _RegionOption(label: tz, timezone: tz));
    setState(() {
      _timezone = tz;
      _region = opt.label;
    });
    await widget.controller.updateSchedule(
        StationScheduleSettingsPatch(timezone: tz, region: opt.label));
  }

  TimeOfDay _parseTime(String? v) {
    final p = (v ?? '00:00').split(':');
    return TimeOfDay(
        hour: int.tryParse(p[0]) ?? 0, minute: int.tryParse(p[1]) ?? 0);
  }
}

// ─── Layout Containers ────────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.settings,
    required this.busy,
    required this.controller,
    required this.pollIntervalSeconds,
    required this.interReadDelay,
    required this.scheduleEnabled,
    required this.selectedDays,
    required this.startTime,
    required this.endTime,
    required this.timezone,
    required this.region,
    required this.onIntervalChanged,
    required this.onDelayChanged,
    required this.onDelayEnd,
    required this.onToggleSensor,
    required this.onEnabled,
    required this.onDayToggle,
    required this.onTimePick,
    required this.onRegionSelect,
    required this.onModeChanged,
    required this.onIntervalDaysChanged,
  });

  final StationSettings settings;
  final bool busy;
  final StationDashboardController controller;
  final int pollIntervalSeconds;
  final double interReadDelay;
  final bool scheduleEnabled;
  final Set<String> selectedDays;
  final String startTime, endTime, timezone, region;
  final ValueChanged<int> onIntervalChanged;
  final ValueChanged<double> onDelayChanged;
  final ValueChanged<double> onDelayEnd;
  final void Function(String, bool) onToggleSensor;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<String> onDayToggle;
  final ValueChanged<bool> onTimePick;
  final ValueChanged<String> onRegionSelect;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<int> onIntervalDaysChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column
        Expanded(
          flex: 5,
          child: Column(
            children: [
              _StationInfoCard(
                deviceId: settings.deviceId,
                stationName: settings.stationName,
                updatedAt: settings.updatedAt,
              ),
              const SizedBox(height: _T.kGap),
              _SectionLabel(
                  title: 'Sensor Modules',
                  sub: 'Enable / disable sensors'),
              const SizedBox(height: 8),
              _SensorTogglesCard(
                  sensors: settings.sensors,
                  busy: busy,
                  onToggle: onToggleSensor),
            ],
          ),
        ),
        const SizedBox(width: _T.kGap + 2),
        // Right column
        Expanded(
          flex: 6,
          child: Column(
            children: [
              _SectionLabel(
                  title: 'Polling Config',
                  sub: 'Hardware & polling matrix'),
              const SizedBox(height: 8),
              _PollingCard(
                interval: pollIntervalSeconds,
                delay: interReadDelay,
                sensorReadOrder: settings.polling.sensorReadOrder,
                busy: busy,
                onIntervalChanged: onIntervalChanged,
                onDelayChanged: onDelayChanged,
                onDelayEnd: onDelayEnd,
              ),
              const SizedBox(height: _T.kGap),
              _SectionLabel(
                  title: 'Sampling Schedule',
                  sub: 'Time-window or interval mode'),
              const SizedBox(height: 8),
              _ScheduleCard(
                schedule: settings.polling.schedule,
                enabled: scheduleEnabled,
                selectedDays: selectedDays,
                startTime: startTime,
                endTime: endTime,
                timezone: timezone,
                region: region,
                busy: busy,
                onEnabled: onEnabled,
                onDayToggle: onDayToggle,
                onTimePick: onTimePick,
                onRegionSelect: onRegionSelect,
                onModeChanged: onModeChanged,
                onIntervalDaysChanged: onIntervalDaysChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({
    required this.settings,
    required this.busy,
    required this.controller,
    required this.pollIntervalSeconds,
    required this.interReadDelay,
    required this.scheduleEnabled,
    required this.selectedDays,
    required this.startTime,
    required this.endTime,
    required this.timezone,
    required this.region,
    required this.onIntervalChanged,
    required this.onDelayChanged,
    required this.onDelayEnd,
    required this.onToggleSensor,
    required this.onEnabled,
    required this.onDayToggle,
    required this.onTimePick,
    required this.onRegionSelect,
    required this.onModeChanged,
    required this.onIntervalDaysChanged,
  });

  final StationSettings settings;
  final bool busy;
  final StationDashboardController controller;
  final int pollIntervalSeconds;
  final double interReadDelay;
  final bool scheduleEnabled;
  final Set<String> selectedDays;
  final String startTime, endTime, timezone, region;
  final ValueChanged<int> onIntervalChanged;
  final ValueChanged<double> onDelayChanged;
  final ValueChanged<double> onDelayEnd;
  final void Function(String, bool) onToggleSensor;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<String> onDayToggle;
  final ValueChanged<bool> onTimePick;
  final ValueChanged<String> onRegionSelect;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<int> onIntervalDaysChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StationInfoCard(
          deviceId: settings.deviceId,
          stationName: settings.stationName,
          updatedAt: settings.updatedAt,
        ),
        const SizedBox(height: _T.kGap + 4),
        _SectionLabel(title: 'Sensor Modules', sub: 'Enable / disable sensors'),
        const SizedBox(height: 8),
        _SensorTogglesCard(
            sensors: settings.sensors, busy: busy, onToggle: onToggleSensor),
        const SizedBox(height: _T.kGap + 4),
        _SectionLabel(title: 'Polling Config', sub: 'Hardware & polling matrix'),
        const SizedBox(height: 8),
        _PollingCard(
          interval: pollIntervalSeconds,
          delay: interReadDelay,
          sensorReadOrder: settings.polling.sensorReadOrder,
          busy: busy,
          onIntervalChanged: onIntervalChanged,
          onDelayChanged: onDelayChanged,
          onDelayEnd: onDelayEnd,
        ),
        const SizedBox(height: _T.kGap + 4),
        _SectionLabel(
            title: 'Sampling Schedule', sub: 'Time-window or interval mode'),
        const SizedBox(height: 8),
        _ScheduleCard(
          schedule: settings.polling.schedule,
          enabled: scheduleEnabled,
          selectedDays: selectedDays,
          startTime: startTime,
          endTime: endTime,
          timezone: timezone,
          region: region,
          busy: busy,
          onEnabled: onEnabled,
          onDayToggle: onDayToggle,
          onTimePick: onTimePick,
          onRegionSelect: onRegionSelect,
          onModeChanged: onModeChanged,
          onIntervalDaysChanged: onIntervalDaysChanged,
        ),
      ],
    );
  }
}

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTokens.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.tune_rounded, size: 18, color: AppTokens.primary),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Station Settings', style: _T.heading(size: 20)),
            Text(
              'Configure sensors, polling & schedule',
              style: _T.micro(size: 11, spacing: 0),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Section Label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.sub});

  final String title, sub;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title,
            style: _T.body(size: 13, weight: FontWeight.w800, color: _T.kText)),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: _T.kBorder, thickness: 1)),
        const SizedBox(width: 8),
        Text(sub, style: _T.micro(size: 10, spacing: 0)),
      ],
    );
  }
}

// ─── Mode Switcher ────────────────────────────────────────────────────────────

class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({required this.mode, required this.onSelected});

  final AppDataMode mode;
  final ValueChanged<AppDataMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _T.kChipBg,
        borderRadius: BorderRadius.circular(_T.kCardRadius),
        border: Border.all(color: _T.kBorder, width: 1),
      ),
      child: Row(
        children: [
          _ModeChip(
            label: 'Cloud',
            icon: Icons.cloud_outlined,
            sel: mode == AppDataMode.supabase,
            onTap: () => onSelected(AppDataMode.supabase),
          ),
          _ModeChip(
            label: 'Live',
            icon: Icons.sensors_rounded,
            sel: mode == AppDataMode.live,
            onTap: () => onSelected(AppDataMode.live),
          ),
          _ModeChip(
            label: 'Mock',
            icon: Icons.science_outlined,
            sel: mode == AppDataMode.mock,
            onTap: () => onSelected(AppDataMode.mock),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip(
      {required this.label,
        required this.icon,
        required this.sel,
        required this.onTap});

  final String label;
  final IconData icon;
  final bool sel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: sel ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: sel
                ? Border.all(color: _T.kBorder, width: 1)
                : Border.all(color: Colors.transparent, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18,
                  color:
                  sel ? AppTokens.primary : _T.kMuted),
              const SizedBox(height: 3),
              Text(label,
                  style: _T.micro(
                      size: 10,
                      spacing: 0,
                      color: sel ? _T.kText : _T.kMuted,
                      weight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Station Info Card ────────────────────────────────────────────────────────

class _StationInfoCard extends StatelessWidget {
  const _StationInfoCard(
      {required this.deviceId, this.stationName, this.updatedAt});

  final String deviceId;
  final String? stationName;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(_T.kPad),
      decoration: _T.card(),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTokens.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.router_rounded,
                color: AppTokens.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stationName ?? 'ESS Station',
                    style: _T.body(size: 14, weight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('ID · $deviceId',
                    style: _T.micro(size: 10, spacing: 0.4)),
              ],
            ),
          ),
          if (updatedAt != null) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('SYNCED', style: _T.micro(size: 8, spacing: 1)),
                const SizedBox(height: 2),
                Text(
                  _fmtDate(updatedAt!),
                  style: _T.body(size: 11, weight: FontWeight.w800,
                      color: AppTokens.primary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

// ─── Sensor Toggles Card ──────────────────────────────────────────────────────

class _SensorTogglesCard extends StatelessWidget {
  const _SensorTogglesCard(
      {required this.sensors,
        required this.busy,
        required this.onToggle});

  final StationSensorSettings sensors;
  final bool busy;
  final void Function(String, bool) onToggle;

  static const _items = [
    (Icons.air_rounded, 'Wind Speed', 'wind_speed'),
    (Icons.explore_rounded, 'Wind Direction', 'wind_direction'),
    (Icons.water_drop_rounded, 'Soil Sensors', 'soil'),
    (Icons.grain_rounded, 'Rain Gauge', 'rain'),
    (Icons.wb_sunny_rounded, 'Solar / UV', 'uv'),
  ];

  bool _val(String key, StationSensorSettings s) {
    switch (key) {
      case 'wind_speed': return s.windSpeedEnabled;
      case 'wind_direction': return s.windDirectionEnabled;
      case 'soil': return s.soilEnabled;
      case 'rain': return s.rainEnabled;
      case 'uv': return s.uvEnabled;
      default: return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _T.card(),
      child: Column(
        children: List.generate(_items.length * 2 - 1, (i) {
          if (i.isOdd) {
            return const Divider(height: 1, thickness: 1, color: _T.kDivider,
                indent: _T.kPad, endIndent: _T.kPad);
          }
          final item = _items[i ~/ 2];
          final enabled = _val(item.$3, sensors);
          return Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: _T.kPad, vertical: 10),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: enabled
                        ? AppTokens.primary.withValues(alpha: 0.10)
                        : _T.kChipBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(item.$1,
                      size: 15,
                      color: enabled ? AppTokens.primary : _T.kMuted),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item.$2,
                      style: _T.body(
                          size: 13,
                          weight: FontWeight.w700,
                          color: enabled ? _T.kText : _T.kMuted)),
                ),
                Transform.scale(
                  scale: 0.82,
                  alignment: Alignment.centerRight,
                  child: Switch.adaptive(
                    value: enabled,
                    activeThumbColor: AppTokens.primary,
                    activeTrackColor:
                    AppTokens.primary.withValues(alpha: 0.20),
                    inactiveThumbColor: const Color(0xFFCDD5DF),
                    inactiveTrackColor: const Color(0xFFEDF0F4),
                    onChanged: busy
                        ? null
                        : (v) => onToggle(item.$3, v),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ─── Polling Config Card ──────────────────────────────────────────────────────

class _PollingCard extends StatelessWidget {
  const _PollingCard({
    required this.interval,
    required this.delay,
    required this.sensorReadOrder,
    required this.busy,
    required this.onIntervalChanged,
    required this.onDelayChanged,
    required this.onDelayEnd,
  });

  final int interval;
  final double delay;
  final List<String> sensorReadOrder;
  final bool busy;
  final ValueChanged<int> onIntervalChanged;
  final ValueChanged<double> onDelayChanged;
  final ValueChanged<double> onDelayEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(_T.kPad),
      decoration: _T.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Interval ──
          _RowLabel(
            icon: Icons.timer_outlined,
            title: 'Polling Frequency',
            badge: _fmtInterval(interval),
            badgeColor: AppTokens.primary,
          ),
          const SizedBox(height: 8),
          _TintedDropdown<int>(
            value: interval,
            accentColor: AppTokens.primary,
            icon: Icons.repeat_rounded,
            items: ({5, 15, 30, 60, 300, 3600, interval}.toList()..sort())
                .map((s) => DropdownMenuItem(
              value: s,
              child: Text('Every ${_fmtInterval(s)}'),
            ))
                .toList(),
            onChanged: busy ? null : (v) { if (v != null) onIntervalChanged(v); },
          ),

          const SizedBox(height: _T.kPad),
          const Divider(height: 1, color: _T.kDivider),
          const SizedBox(height: _T.kPad),

          // ── Delay slider ──
          _RowLabel(
            icon: Icons.speed_outlined,
            title: 'Sensor Read Gap',
            badge: '${delay.round()} ms',
            badgeColor: const Color(0xFF8B5CF6),
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape:
              const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape:
              const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: AppTokens.primary,
              inactiveTrackColor: _T.kChipBg,
              thumbColor: AppTokens.primary,
              overlayColor: AppTokens.primary.withValues(alpha: 0.12),
            ),
            child: Slider(
              value: delay.clamp(0, 5000),
              min: 0,
              max: 5000,
              onChanged: busy ? null : onDelayChanged,
              onChangeEnd: busy ? null : onDelayEnd,
            ),
          ),

          const SizedBox(height: _T.kPad),
          const Divider(height: 1, color: _T.kDivider),
          const SizedBox(height: _T.kPad),

          // ── Read order ──
          _RowLabel(
            icon: Icons.reorder_rounded,
            title: 'Read Order',
            badge: '${sensorReadOrder.length} sensors',
            badgeColor: _T.kMuted,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(sensorReadOrder.length, (i) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: _T.kChipBg,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: _T.kBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${i + 1}',
                        style: _T.micro(
                            size: 9,
                            color: AppTokens.primary,
                            spacing: 0,
                            weight: FontWeight.w800)),
                    const SizedBox(width: 5),
                    Text(sensorReadOrder[i].toUpperCase(),
                        style: _T.micro(
                            size: 9,
                            spacing: 0.7,
                            color: _T.kSub)),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─── Schedule Card ────────────────────────────────────────────────────────────

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.enabled,
    required this.selectedDays,
    required this.startTime,
    required this.endTime,
    required this.timezone,
    required this.region,
    required this.busy,
    required this.onEnabled,
    required this.onDayToggle,
    required this.onTimePick,
    required this.onRegionSelect,
    required this.onModeChanged,
    required this.onIntervalDaysChanged,
  });

  final StationScheduleSettings schedule;
  final bool enabled;
  final Set<String> selectedDays;
  final String startTime, endTime, timezone, region;
  final bool busy;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<String> onDayToggle;
  final ValueChanged<bool> onTimePick;
  final ValueChanged<String> onRegionSelect;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<int> onIntervalDaysChanged;

  bool get _isWindow => schedule.mode == 'window';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(_T.kPad),
      decoration: _T.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle row
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: enabled
                      ? AppTokens.primary.withValues(alpha: 0.10)
                      : _T.kChipBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.calendar_today_rounded,
                    size: 14,
                    color: enabled ? AppTokens.primary : _T.kMuted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sampling Schedule',
                        style: _T.body(size: 13, weight: FontWeight.w800)),
                    Text(enabled ? 'Active' : 'Disabled',
                        style: _T.micro(
                            size: 10,
                            spacing: 0,
                            color: enabled
                                ? AppTokens.primary
                                : _T.kMuted)),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.82,
                alignment: Alignment.centerRight,
                child: Switch.adaptive(
                  value: enabled,
                  activeThumbColor: AppTokens.primary,
                  activeTrackColor: AppTokens.primary.withValues(alpha: 0.20),
                  inactiveThumbColor: const Color(0xFFCDD5DF),
                  inactiveTrackColor: const Color(0xFFEDF0F4),
                  onChanged: busy ? null : onEnabled,
                ),
              ),
            ],
          ),

          if (enabled) ...[
            const SizedBox(height: _T.kPad),
            const Divider(height: 1, color: _T.kDivider),
            const SizedBox(height: _T.kPad),

            // Mode toggle pill
            _ModeTogglePill(
                currentMode: schedule.mode,
                busy: busy,
                onChanged: onModeChanged),

            const SizedBox(height: _T.kPad),

            // Region
            Row(
              children: [
                Text('REGION', style: _T.micro(size: 9, spacing: 1.1)),
                const SizedBox(width: 8),
                Expanded(
                    child: Divider(color: _T.kBorder, thickness: 1)),
              ],
            ),
            const SizedBox(height: 6),
            _TintedDropdown<String>(
              value: timezone,
              accentColor: const Color(0xFF0EA5E9),
              icon: Icons.public_rounded,
              items: (() {
                final opts = _regionOptions
                    .map((o) => DropdownMenuItem(
                  value: o.timezone,
                  child: Text('${o.label}  ·  ${o.timezone}',
                      overflow: TextOverflow.ellipsis),
                ))
                    .toList();
                if (!_regionOptions.any((o) => o.timezone == timezone)) {
                  opts.add(DropdownMenuItem(
                      value: timezone,
                      child: Text('Custom · $timezone',
                          overflow: TextOverflow.ellipsis)));
                }
                return opts;
              })(),
              onChanged: busy
                  ? null
                  : (v) { if (v != null) onRegionSelect(v); },
            ),

            const SizedBox(height: _T.kPad),

            if (_isWindow) ...[
              // Day picker
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _dayLabels.entries.map((e) {
                  final sel = selectedDays.contains(e.key);
                  return GestureDetector(
                    onTap: busy ? null : () => onDayToggle(e.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: sel
                            ? AppTokens.primary
                            : _T.kChipBg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: sel
                              ? AppTokens.primary
                              : _T.kBorder,
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(e.value,
                            style: _T.micro(
                                size: 11,
                                spacing: 0,
                                weight: FontWeight.w800,
                                color: sel
                                    ? Colors.white
                                    : _T.kMuted)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: _T.kPad),

              // Time tiles
              Row(
                children: [
                  Expanded(
                      child: _TimeTileCompact(
                          label: 'Start',
                          time: startTime,
                          onTap: () => onTimePick(true))),
                  const SizedBox(width: _T.kGap),
                  Expanded(
                      child: _TimeTileCompact(
                          label: 'End',
                          time: endTime,
                          onTap: () => onTimePick(false))),
                ],
              ),
            ] else ...[
              // Interval mode
              Row(
                children: [
                  Text('REPEAT EVERY', style: _T.micro(size: 9, spacing: 1.1)),
                  const SizedBox(width: 8),
                  Expanded(child: Divider(color: _T.kBorder)),
                ],
              ),
              const SizedBox(height: 6),
              _TintedDropdown<int>(
                value: schedule.intervalDays,
                accentColor: const Color(0xFFF59E0B),
                icon: Icons.repeat_one_rounded,
                items: List.generate(30, (i) => i + 1)
                    .map((d) => DropdownMenuItem(
                  value: d,
                  child: Text(
                      '$d ${d == 1 ? 'Day' : 'Days'}'),
                ))
                    .toList(),
                onChanged: busy
                    ? null
                    : (v) {
                  if (v != null) onIntervalDaysChanged(v);
                },
              ),

              if (schedule.runTimes.isNotEmpty) ...[
                const SizedBox(height: _T.kPad),
                _RowLabel(
                  icon: Icons.access_time_rounded,
                  title: 'Run Times',
                  badge: '${schedule.runTimes.length}',
                  badgeColor: const Color(0xFFF59E0B),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: schedule.runTimes
                      .map((t) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                          color: const Color(0xFFFDE68A)),
                    ),
                    child: Text(t,
                        style: _T.body(
                            size: 11,
                            weight: FontWeight.w800,
                            color: const Color(0xFFB45309))),
                  ))
                      .toList(),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

// ─── Mode Toggle Pill ─────────────────────────────────────────────────────────

class _ModeTogglePill extends StatelessWidget {
  const _ModeTogglePill(
      {required this.currentMode,
        required this.busy,
        required this.onChanged});

  final String currentMode;
  final bool busy;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _T.kChipBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _T.kBorder),
      ),
      child: Row(
        children: ['window', 'interval'].map((m) {
          final sel = currentMode == m;
          return Expanded(
            child: GestureDetector(
              onTap: busy ? null : () => onChanged(m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: sel
                      ? Border.all(color: _T.kBorder, width: 1)
                      : null,
                ),
                child: Center(
                  child: Text(
                    m == 'window' ? 'Window' : 'Interval',
                    style: _T.micro(
                      size: 11,
                      spacing: 0,
                      weight: FontWeight.w800,
                      color: sel ? _T.kText : _T.kMuted,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Atoms ────────────────────────────────────────────────────────────────────

/// Reusable colored tinted dropdown (no plain white bg)
class _TintedDropdown<T> extends StatelessWidget {
  const _TintedDropdown({
    required this.value,
    required this.accentColor,
    required this.icon,
    required this.items,
    required this.onChanged,
  });

  final T? value;
  final Color accentColor;
  final IconData icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(_T.kInnerRadius),
        border: Border.all(color: accentColor.withValues(alpha: 0.18), width: 1),
      ),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        dropdownColor: Colors.white,
        icon: Icon(Icons.unfold_more_rounded,
            size: 16, color: _T.kMuted),
        style: _T.body(size: 13),
        decoration: InputDecoration(
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 10, right: 4),
            child: Icon(icon, size: 15, color: accentColor),
          ),
          prefixIconConstraints:
          const BoxConstraints(minWidth: 32, minHeight: 0),
          filled: false,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

/// Compact time tile
class _TimeTileCompact extends StatelessWidget {
  const _TimeTileCompact(
      {required this.label, required this.time, required this.onTap});

  final String label, time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTokens.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(_T.kInnerRadius),
          border: Border.all(
              color: AppTokens.primary.withValues(alpha: 0.18), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded,
                size: 14, color: AppTokens.primary),
            const SizedBox(width: 7),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: _T.micro(
                        size: 8,
                        spacing: 0.8,
                        color: AppTokens.primary)),
                Text(time,
                    style: _T.body(
                        size: 14,
                        weight: FontWeight.w800,
                        color: _T.kText)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Row label with trailing badge
class _RowLabel extends StatelessWidget {
  const _RowLabel({
    required this.icon,
    required this.title,
    required this.badge,
    required this.badgeColor,
  });

  final IconData icon;
  final String title, badge;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _T.kMuted),
        const SizedBox(width: 6),
        Expanded(
            child:
            Text(title, style: _T.body(size: 12, weight: FontWeight.w700))),
        Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(badge,
              style: _T.micro(
                  size: 9,
                  spacing: 0.3,
                  color: badgeColor,
                  weight: FontWeight.w800)),
        ),
      ],
    );
  }
}

// ─── Utilities ────────────────────────────────────────────────────────────────

String _fmtInterval(int s) {
  if (s < 60) return '${s}s';
  if (s < 3600) return '${s ~/ 60}m';
  return '${s ~/ 3600}h';
}

class _RegionOption {
  const _RegionOption({required this.label, required this.timezone});
  final String label, timezone;
}
