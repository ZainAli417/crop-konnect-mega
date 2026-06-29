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
              if (widget.controller.errorMessage != null) ...[
                const SizedBox(height: 10),
                _SettingsErrorStrip(message: widget.controller.errorMessage!),
              ],

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
                          onIntervalChanged: (v) {
                            setState(() => _pollIntervalSeconds = v);
                            widget.controller
                                .updatePolling(pollIntervalSeconds: v);
                          },
                          onDelayChanged: (v) =>
                              setState(() => _interReadDelay = v),
                          onDelayEnd: (v) => widget.controller
                              .updatePolling(interReadDelayMs: v.round()),
                          onToggleSensor: (k, val) =>
                              widget.controller.setSensorEnabled(k, val),
                          onSensorIntervalChanged:
                              widget.controller.updateSensorInterval,
                        )
                      : _NarrowLayout(
                          settings: settings,
                          busy: busy,
                          controller: widget.controller,
                          pollIntervalSeconds: _pollIntervalSeconds!,
                          interReadDelay: _interReadDelay!,
                          onIntervalChanged: (v) {
                            setState(() => _pollIntervalSeconds = v);
                            widget.controller
                                .updatePolling(pollIntervalSeconds: v);
                          },
                          onDelayChanged: (v) =>
                              setState(() => _interReadDelay = v),
                          onDelayEnd: (v) => widget.controller
                              .updatePolling(interReadDelayMs: v.round()),
                          onToggleSensor: (k, val) =>
                              widget.controller.setSensorEnabled(k, val),
                          onSensorIntervalChanged:
                              widget.controller.updateSensorInterval,
                        );
                }),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SettingsErrorStrip extends StatelessWidget {
  const _SettingsErrorStrip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: Color(0xFFBE123C)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: _T.body(
                size: 12,
                weight: FontWeight.w700,
                color: const Color(0xFF9F1239),
              ),
            ),
          ),
        ],
      ),
    );
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
    required this.onIntervalChanged,
    required this.onDelayChanged,
    required this.onDelayEnd,
    required this.onToggleSensor,
    required this.onSensorIntervalChanged,
  });

  final StationSettings settings;
  final bool busy;
  final StationDashboardController controller;
  final int pollIntervalSeconds;
  final double interReadDelay;
  final ValueChanged<int> onIntervalChanged;
  final ValueChanged<double> onDelayChanged;
  final ValueChanged<double> onDelayEnd;
  final void Function(String, bool) onToggleSensor;
  final void Function(String, int) onSensorIntervalChanged;

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
                  title: 'Sensor Modules', sub: 'Enable / disable sensors'),
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
                  title: 'Backend Loop', sub: 'Fallback poll and read gap'),
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
                  title: 'Sensor Intervals',
                  sub: 'Dedicated read timing per sensor'),
              const SizedBox(height: 8),
              _SensorIntervalsCard(
                sensors: settings.sensors,
                intervals: settings.polling.sensorIntervals,
                busy: busy,
                onChanged: onSensorIntervalChanged,
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
    required this.onIntervalChanged,
    required this.onDelayChanged,
    required this.onDelayEnd,
    required this.onToggleSensor,
    required this.onSensorIntervalChanged,
  });

  final StationSettings settings;
  final bool busy;
  final StationDashboardController controller;
  final int pollIntervalSeconds;
  final double interReadDelay;
  final ValueChanged<int> onIntervalChanged;
  final ValueChanged<double> onDelayChanged;
  final ValueChanged<double> onDelayEnd;
  final void Function(String, bool) onToggleSensor;
  final void Function(String, int) onSensorIntervalChanged;

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
        _SectionLabel(title: 'Backend Loop', sub: 'Fallback poll and read gap'),
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
            title: 'Sensor Intervals', sub: 'Dedicated read timing per sensor'),
        const SizedBox(height: 8),
        _SensorIntervalsCard(
          sensors: settings.sensors,
          intervals: settings.polling.sensorIntervals,
          busy: busy,
          onChanged: onSensorIntervalChanged,
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
              'Configure sensors, polling & intervals',
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
              Icon(icon, size: 18, color: sel ? AppTokens.primary : _T.kMuted),
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
            child:
                Icon(Icons.router_rounded, color: AppTokens.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stationName ?? 'ESS Station',
                    style: _T.body(size: 14, weight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('ID · $deviceId', style: _T.micro(size: 10, spacing: 0.4)),
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
                  style: _T.body(
                      size: 11,
                      weight: FontWeight.w800,
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
      {required this.sensors, required this.busy, required this.onToggle});

  final StationSensorSettings sensors;
  final bool busy;
  final void Function(String, bool) onToggle;

  static const _items = [
    (Icons.air_rounded, 'Wind Sensor', 'wind'),
    (Icons.water_drop_rounded, 'Soil Sensors', 'soil'),
    (Icons.grain_rounded, 'Rain Gauge', 'rain'),
    (Icons.wb_sunny_rounded, 'Solar / UV', 'uv'),
  ];

  bool _val(String key, StationSensorSettings s) {
    switch (key) {
      case 'wind':
        return s.windEnabled;
      case 'soil':
        return s.soilEnabled;
      case 'rain':
        return s.rainEnabled;
      case 'uv':
        return s.uvEnabled;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _T.card(),
      child: Column(
        children: List.generate(_items.length * 2 - 1, (i) {
          if (i.isOdd) {
            return const Divider(
                height: 1,
                thickness: 1,
                color: _T.kDivider,
                indent: _T.kPad,
                endIndent: _T.kPad);
          }
          final item = _items[i ~/ 2];
          final enabled = _val(item.$3, sensors);
          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: _T.kPad, vertical: 10),
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
                      size: 15, color: enabled ? AppTokens.primary : _T.kMuted),
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
                    activeTrackColor: AppTokens.primary.withValues(alpha: 0.20),
                    inactiveThumbColor: const Color(0xFFCDD5DF),
                    inactiveTrackColor: const Color(0xFFEDF0F4),
                    onChanged: busy ? null : (v) => onToggle(item.$3, v),
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
            title: 'Fallback Poll',
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
                      child: Text(_fmtEveryInterval(s)),
                    ))
                .toList(),
            onChanged: busy
                ? null
                : (v) {
                    if (v != null) onIntervalChanged(v);
                  },
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
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
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
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
                        style: _T.micro(size: 9, spacing: 0.7, color: _T.kSub)),
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

// ─── Sensor Intervals Card ─────────────────────────────────────────────────────

class _SensorIntervalsCard extends StatelessWidget {
  const _SensorIntervalsCard({
    required this.sensors,
    required this.intervals,
    required this.busy,
    required this.onChanged,
  });

  final StationSensorSettings sensors;
  final Map<String, SensorIntervalSettings> intervals;
  final bool busy;
  final void Function(String, int) onChanged;

  static const _items = [
    (Icons.air_rounded, 'Wind Sensor', 'wind', Color(0xFF0EA5E9)),
    (Icons.water_drop_rounded, 'Soil Sensors', 'soil', Color(0xFF10B981)),
    (Icons.grain_rounded, 'Rain Gauge', 'rain', Color(0xFF6366F1)),
    (Icons.wb_sunny_rounded, 'Solar / UV', 'uv', Color(0xFFF59E0B)),
  ];

  static const List<int> _intervalOptions = <int>[
    5,
    15,
    30,
    60,
    120,
    300,
    600,
    900,
    1800,
    2700,
    3600,
    7200,
    14400,
    21600,
    43200,
    86400,
  ];

  bool _sensorEnabled(String key) {
    switch (key) {
      case 'wind':
        return sensors.windEnabled;
      case 'soil':
        return sensors.soilEnabled;
      case 'rain':
        return sensors.rainEnabled;
      case 'uv':
        return sensors.uvEnabled;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _T.card(),
      child: Column(
        children: List.generate(_items.length * 2 - 1, (i) {
          if (i.isOdd) {
            return const Divider(
              height: 1,
              thickness: 1,
              color: _T.kDivider,
              indent: _T.kPad,
              endIndent: _T.kPad,
            );
          }
          final item = _items[i ~/ 2];
          final key = item.$3;
          final enabled = _sensorEnabled(key);
          final current =
              intervals[key]?.intervalSeconds ?? kDefaultSensorIntervalSeconds;
          final options = ({..._intervalOptions, current}.toList()..sort());
          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: _T.kPad, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color:
                        enabled ? item.$4.withValues(alpha: 0.10) : _T.kChipBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    item.$1,
                    size: 15,
                    color: enabled ? item.$4 : _T.kMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$2,
                        style: _T.body(
                          size: 13,
                          weight: FontWeight.w800,
                          color: enabled ? _T.kText : _T.kMuted,
                        ),
                      ),
                      Text(
                        enabled ? _fmtEveryInterval(current) : 'Off',
                        style: _T.micro(
                          size: 10,
                          spacing: 0,
                          color: enabled ? item.$4 : _T.kMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 150,
                  child: _TintedDropdown<int>(
                    value: current,
                    accentColor: item.$4,
                    icon: Icons.timer_outlined,
                    items: options
                        .map(
                          (seconds) => DropdownMenuItem<int>(
                            value: seconds,
                            child: Text(_fmtEveryInterval(seconds)),
                          ),
                        )
                        .toList(),
                    onChanged: busy || !enabled
                        ? null
                        : (value) {
                            if (value != null) onChanged(key, value);
                          },
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
        border:
            Border.all(color: accentColor.withValues(alpha: 0.18), width: 1),
      ),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        dropdownColor: Colors.white,
        icon: Icon(Icons.unfold_more_rounded, size: 16, color: _T.kMuted),
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
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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

String _fmtEveryInterval(int seconds) {
  if (seconds == 5) return 'Live (5s)';
  return 'Every ${_fmtInterval(seconds)}';
}
