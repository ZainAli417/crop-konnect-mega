import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/dashboard_theme.dart';
import '../models/irrigation.dart';
import '../models/sensor_reading.dart';
import '../viewmodels/station_dashboard_controller.dart';

// ─── Design Tokens (local overrides for this tab) ─────────────────────────────

class _T {
  _T._();

  // Layout
  static const double kCardRadius = 16;
  static const double kInnerRadius = 10;
  static const double kPad = 14;
  static const double kGap = 10;
  static const double kColBreak = 720; // px – switches to two-column

  // Elevation replacement: subtle layered border + tint
  static BoxDecoration card() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(kCardRadius),
    border: Border.all(color: const Color(0xFFE8EDF2), width: 1),
  );

  // Typography helpers – Plus Jakarta Sans only
  static TextStyle label({
    double size = 10,
    FontWeight weight = FontWeight.w700,
    Color color = const Color(0xFF8899AA),
    double spacing = 0.8,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
      );

  static TextStyle body({
    double size = 13,
    FontWeight weight = FontWeight.w600,
    Color color = const Color(0xFF1A2433),
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
      );

  static TextStyle heading({
    double size = 22,
    FontWeight weight = FontWeight.w800,
    Color color = const Color(0xFF0D1821),
    double spacing = -0.5,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
      );
}

// ─── Irrigation Tab ───────────────────────────────────────────────────────────

class IrrigationTab extends StatelessWidget {
  const IrrigationTab({super.key, required this.controller});

  final StationDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return RefreshIndicator(
          onRefresh: controller.refreshIrrigation,
          color: AppTokens.primary,
          backgroundColor: Colors.white,
          displacement: 20,
          child: ListView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            children: [
              _PageHeader(),
              const SizedBox(height: 14),
              SectionReveal(
                delay: Duration.zero,
                child: LayoutBuilder(
                  builder: (ctx, constraints) {
                    final wide = constraints.maxWidth >= _T.kColBreak;
                    if (wide) {
                      return _TwoColumnLayout(controller: controller);
                    }
                    return _SingleColumnLayout(controller: controller);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

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
          child: Icon(Icons.water_drop_rounded,
              size: 18, color: AppTokens.primary),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Irrigation Manager', style: _T.heading(size: 20)),
            Text(
              'Target-based moisture & growth tracking',
              style: _T.label(size: 11, spacing: 0),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Layout Variants ──────────────────────────────────────────────────────────

class _TwoColumnLayout extends StatelessWidget {
  const _TwoColumnLayout({required this.controller});

  final StationDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: RepaintBoundary(
            child: _SmartIrrigationCard(controller: controller),
          ),
        ),
        const SizedBox(width: _T.kGap + 2),
        Expanded(
          flex: 6,
          child: RepaintBoundary(
            child: _IrrigationAdvisoryCard(
              profile: controller.irrigationProfile,
              advisory: controller.latestIrrigationAdvisory,
              reading: controller.latestReading,
            ),
          ),
        ),
      ],
    );
  }
}

class _SingleColumnLayout extends StatelessWidget {
  const _SingleColumnLayout({required this.controller});

  final StationDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SmartIrrigationCard(controller: controller),
        const SizedBox(height: _T.kGap + 2),
        _IrrigationAdvisoryCard(
          profile: controller.irrigationProfile,
          advisory: controller.latestIrrigationAdvisory,
          reading: controller.latestReading,
        ),
      ],
    );
  }
}

// ─── Smart Irrigation Card ────────────────────────────────────────────────────

class _SmartIrrigationCard extends StatefulWidget {
  const _SmartIrrigationCard({required this.controller});

  final StationDashboardController controller;

  @override
  State<_SmartIrrigationCard> createState() => _SmartIrrigationCardState();
}

class _SmartIrrigationCardState extends State<_SmartIrrigationCard> {
  String? _selectedCrop;
  String? _selectedStage;
  bool? _enabled;

  String? _activeCrop(
      List<IrrigationCropOption> presets, IrrigationProfile? profile) {
    final candidate = _selectedCrop ?? profile?.crop;
    if (candidate != null && presets.any((item) => item.crop == candidate)) {
      return candidate;
    }
    return presets.isEmpty ? null : presets.first.crop;
  }

  List<String> _stagesFor(
      List<IrrigationCropOption> presets, String? crop) {
    if (crop == null) return const [];
    return presets
        .firstWhere((item) => item.crop == crop,
        orElse: () =>
        const IrrigationCropOption(crop: '', stages: []))
        .stages;
  }

  String? _activeStage(List<String> stages, IrrigationProfile? profile) {
    final candidate = _selectedStage ?? profile?.cropStage;
    if (candidate != null && stages.contains(candidate)) return candidate;
    return stages.isEmpty ? null : stages.first;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final presets = ctrl.irrigationPresets;
    final profile = ctrl.irrigationProfile;
    final enabled = _enabled ?? profile?.smartIrrigationEnabled ?? false;
    final crop = _activeCrop(presets, profile);
    final stages = _stagesFor(presets, crop);
    final stage = _activeStage(stages, profile);
    final busy = ctrl.isApplyingIrrigation;
    final statusColor = enabled ? AppTokens.primary : const Color(0xFFB0BBC8);

    return Container(
      decoration: _T.card(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                _T.kPad, _T.kPad, _T.kPad - 2, _T.kPad - 2),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.psychology_rounded,
                      size: 16, color: statusColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Smart Advisory',
                          style: _T.body(
                              size: 14, weight: FontWeight.w800)),
                      Text(
                        enabled ? 'AI engine active' : 'Advisory paused',
                        style: _T.label(
                            size: 10,
                            color: statusColor,
                            spacing: 0),
                      ),
                    ],
                  ),
                ),
                _CompactSwitch(
                  value: enabled,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => _enabled = v),
                ),
              ],
            ),
          ),

          // ── Divider ─────────────────────────────────────────────────────
          const Divider(height: 1, thickness: 1, color: Color(0xFFF0F3F7)),

          // ── Dropdowns ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(_T.kPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Inline label row
                Row(
                  children: [
                    Text('CROP TYPE',
                        style: _T.label(size: 9, spacing: 1.1)),
                    const SizedBox(width: _T.kGap),
                    Expanded(
                        child:
                        Divider(color: const Color(0xFFEDF0F4))),
                  ],
                ),
                const SizedBox(height: 6),
                _StyledDropdown(
                  value: crop,
                  items: presets.map((e) => e.crop).toList(),
                  icon: Icons.grass_rounded,
                  accentColor: const Color(0xFF34A853),
                  onChanged: (v) {
                    if (v == null) return;
                    final ns = _stagesFor(presets, v);
                    setState(() {
                      _selectedCrop = v;
                      _selectedStage =
                      ns.isEmpty ? null : ns.first;
                    });
                  },
                ),

                const SizedBox(height: _T.kPad - 2),

                Row(
                  children: [
                    Text('GROWTH STAGE',
                        style: _T.label(size: 9, spacing: 1.1)),
                    const SizedBox(width: _T.kGap),
                    Expanded(
                        child:
                        Divider(color: const Color(0xFFEDF0F4))),
                  ],
                ),
                const SizedBox(height: 6),
                _StyledDropdown(
                  value: stage,
                  items: stages,
                  icon: Icons.auto_graph_rounded,
                  accentColor: AppTokens.primary,
                  onChanged: (v) => setState(() => _selectedStage = v),
                ),

                const SizedBox(height: _T.kPad),

                // ── Footer ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FA),
                    borderRadius: BorderRadius.circular(_T.kInnerRadius),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded,
                          size: 13, color: const Color(0xFF99AABB)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          profile == null
                              ? 'Configure presets to begin'
                              : 'Band: ${formatNumber(profile.moistureLowerTarget)}% – ${formatNumber(profile.moistureUpperTarget)}%',
                          style: _T.label(size: 11, spacing: 0),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ApplyButton(
                        busy: busy,
                        onTap: () =>
                            widget.controller.updateSmartIrrigation(
                              enabled: enabled,
                              crop: crop,
                              cropStage: stage,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Advisory Card ────────────────────────────────────────────────────────────

class _IrrigationAdvisoryCard extends StatelessWidget {
  const _IrrigationAdvisoryCard({
    required this.profile,
    required this.advisory,
    required this.reading,
  });

  final IrrigationProfile? profile;
  final IrrigationAdvisory? advisory;
  final SensorReading? reading;

  @override
  Widget build(BuildContext context) {
    final enabled = profile?.smartIrrigationEnabled ?? false;
    final accent = advisory == null
        ? const Color(0xFF4A90D9)
        : irrigationDecisionColor(advisory!.decision);
    final title = advisory?.title ??
        (enabled ? 'Analyzing Data…' : 'Advisory Inactive');

    return Container(
      decoration: _T.card(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Accent banner ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(_T.kPad),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.05),
              border: Border(
                  bottom: BorderSide(
                      color: accent.withValues(alpha: 0.15), width: 1)),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_T.kCardRadius)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AdvisoryIconBox(color: accent, advisory: advisory),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: _T.heading(size: 15, spacing: -0.2)),
                      const SizedBox(height: 3),
                      Text(
                        advisory?.message ??
                            'Enable smart monitoring to receive insights.',
                        style: _T.label(
                            size: 12,
                            spacing: 0,
                            color: const Color(0xFF6B7E92)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    humanize(advisory?.urgency ?? 'stable')
                        .toUpperCase(),
                    style: _T.label(
                        size: 9,
                        spacing: 0.8,
                        color: accent,
                        weight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),

          // ── Metrics grid ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(_T.kPad),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MetricChip(
                        label: 'MOISTURE',
                        value: formatMetric(
                            advisory?.moistureValue ?? reading?.moist,
                            suffix: '%'),
                        icon: Icons.water_drop_outlined,
                        bg: const Color(0xFFEEF6FF),
                        fg: const Color(0xFF3B82F6),
                      ),
                    ),
                    const SizedBox(width: _T.kGap),
                    Expanded(
                      child: _MetricChip(
                        label: 'TARGET RANGE',
                        value:
                        '${formatNumber(advisory?.lowerTarget ?? profile?.moistureLowerTarget)}–${formatNumber(advisory?.upperTarget ?? profile?.moistureUpperTarget)}%',
                        icon: Icons.straighten_rounded,
                        bg: const Color(0xFFEFFAF0),
                        fg: const Color(0xFF22C55E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: _T.kGap),
                Row(
                  children: [
                    Expanded(
                      child: _MetricChip(
                        label: 'CURRENT CROP',
                        value: profile?.crop ?? '--',
                        icon: Icons.grass_outlined,
                        bg: const Color(0xFFFFF7ED),
                        fg: const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: _T.kGap),
                    Expanded(
                      child: _MetricChip(
                        label: 'URGENCY',
                        value: humanize(advisory?.urgency ?? 'stable'),
                        icon: Icons.flag_outlined,
                        bg: accent.withValues(alpha: 0.08),
                        fg: accent,
                      ),
                    ),
                  ],
                ),

                // ── Reason note ───────────────────────────────────────
                if (advisory?.reason.isNotEmpty ?? false) ...[
                  const SizedBox(height: _T.kGap),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F8FA),
                      borderRadius:
                      BorderRadius.circular(_T.kInnerRadius),
                      border: Border.all(
                          color: const Color(0xFFE8EDF2), width: 1),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(Icons.info_outline_rounded,
                              size: 12,
                              color: const Color(0xFF99AABB)),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(advisory!.reason,
                              style: _T.label(
                                  size: 11,
                                  spacing: 0,
                                  color: const Color(0xFF6B7E92))),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Atoms ────────────────────────────────────────────────────────────────────

/// Compact, styled dropdown with colored left-accent strip
class _StyledDropdown extends StatelessWidget {
  const _StyledDropdown({
    required this.value,
    required this.items,
    required this.icon,
    required this.accentColor,
    required this.onChanged,
  });

  final String? value;
  final List<String> items;
  final IconData icon;
  final Color accentColor;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(_T.kInnerRadius),
        border: Border.all(color: accentColor.withValues(alpha: 0.2), width: 1),
      ),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        dropdownColor: Colors.white,
        icon: Icon(Icons.unfold_more_rounded,
            size: 16, color: const Color(0xFFAABBCC)),
        decoration: InputDecoration(
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 10, right: 4),
            child: Icon(icon, size: 16, color: accentColor),
          ),
          prefixIconConstraints:
          const BoxConstraints(minWidth: 34, minHeight: 0),
          filled: false,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 10),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        style: _T.body(size: 13),
        items: items
            .map((e) => DropdownMenuItem(
          value: e,
          child: Text(e,
              style: _T.body(size: 13, weight: FontWeight.w700)),
        ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

/// Tinted metric chip replacing plain FactTile
class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.bg,
    required this.fg,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(_T.kInnerRadius),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: _T.label(size: 9, spacing: 0.6, color: fg)),
                const SizedBox(height: 1),
                Text(value,
                    style: _T.body(
                        size: 12,
                        weight: FontWeight.w800,
                        color: fg)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Advisory status icon box
class _AdvisoryIconBox extends StatelessWidget {
  const _AdvisoryIconBox(
      {required this.color, this.advisory});

  final Color color;
  final IrrigationAdvisory? advisory;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        advisory == null
            ? Icons.data_usage_rounded
            : irrigationDecisionIcon(advisory!.decision),
        color: color,
        size: 20,
      ),
    );
  }
}

/// Custom compact toggle
class _CompactSwitch extends StatelessWidget {
  const _CompactSwitch({required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.82,
      alignment: Alignment.centerRight,
      child: Switch.adaptive(
        value: value,
        activeThumbColor: AppTokens.primary,
        activeTrackColor: AppTokens.primary.withValues(alpha: 0.22),
        inactiveThumbColor: const Color(0xFFCDD5DF),
        inactiveTrackColor: const Color(0xFFEDF0F4),
        onChanged: onChanged,
      ),
    );
  }
}

/// Compact inline apply button
class _ApplyButton extends StatelessWidget {
  const _ApplyButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: busy ? const Color(0xFFE8EDF2) : AppTokens.forest,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF99AABB)),
              )
            else
              const Icon(Icons.check_rounded,
                  color: Colors.white, size: 13),
            const SizedBox(width: 5),
            Text(
              busy ? 'SAVING' : 'APPLY',
              style: _T.label(
                size: 10,
                spacing: 0.8,
                weight: FontWeight.w800,
                color: busy
                    ? const Color(0xFF99AABB)
                    : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
