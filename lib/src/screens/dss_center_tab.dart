import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/dashboard_theme.dart';
import '../models/soil_weather_advisory.dart';
import '../viewmodels/station_dashboard_controller.dart';

// ════════════════════════════════════════════════════════════════════════════
//  DSS Center — Soil & Weather Advisory (remote)
//  Pick a crop + sowing date → the growth stage is drawn on an animated
//  timeline, and the field's latest soil + weather readings are sent to the
//  advisory backend. The returned advisory (summary, action points, focus
//  items, narrative sections and per-parameter signal comparisons) is rendered
//  below. A language toggle switches the advisory between English and Urdu.
// ════════════════════════════════════════════════════════════════════════════

class DssCenterTab extends StatelessWidget {
  const DssCenterTab({super.key, required this.controller});

  final StationDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final advisory = controller.soilWeatherAdvisory;
        final rtl = controller.advisoryLanguage == 'ur';
        return RefreshIndicator(
          onRefresh: controller.refreshSoilWeatherAdvisory,
          color: AppTokens.primary,
          backgroundColor: Colors.white,
          child: Container(
            color: const Color(0xFFF6F8FB),
            child: ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
              children: [
                _Header(advisory: advisory, controller: controller),
                const SizedBox(height: 14),
                _SelectionCard(controller: controller),
                const SizedBox(height: 14),

                if (controller.isLoadingAdvisory && advisory == null)
                  const _LoadingDssCard()
                else if (controller.soilWeatherError != null && advisory == null)
                  _ErrorCard(message: controller.soilWeatherError!)
                else if (advisory == null)
                  const _EmptyPrompt()
                else ...[
                  if (controller.isLoadingAdvisory)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        color: AppTokens.primary,
                        backgroundColor: Color(0xFFE8EDF3),
                      ),
                    ),
                  _SummaryHero(advisory: advisory, rtl: rtl),
                  const SizedBox(height: 14),

                  if (advisory.specialFocus.isNotEmpty) ...[
                    _SpecialFocusCard(advisory: advisory, rtl: rtl),
                    const SizedBox(height: 14),
                  ],
                  if (advisory.actionPoints.isNotEmpty) ...[
                    _ActionPointsCard(advisory: advisory, rtl: rtl),
                    const SizedBox(height: 14),
                  ],
                  if (advisory.sections.isNotEmpty) ...[
                    _SectionsCard(advisory: advisory, rtl: rtl),
                    const SizedBox(height: 14),
                  ],
                  if (advisory.soilSignals.isNotEmpty) ...[
                    _SignalsCard(
                      title: 'Soil readings',
                      icon: Icons.terrain_rounded,
                      signals: advisory.soilSignals,
                      rtl: rtl,
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (advisory.weatherSignals.isNotEmpty)
                    _SignalsCard(
                      title: 'Weather readings',
                      icon: Icons.wb_cloudy_rounded,
                      signals: advisory.weatherSignals,
                      rtl: rtl,
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────── Header ──

class _Header extends StatelessWidget {
  const _Header({required this.advisory, required this.controller});

  final SoilWeatherAdvisory? advisory;
  final StationDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final crop = advisory?.cropName.isNotEmpty == true
        ? advisory!.cropName
        : (controller.activeTimeline?.crop ?? controller.selectedCropId);
    final stage = advisory?.stage ?? '';
    final subtitle = advisory == null
        ? 'Building your field advisory'
        : stage.isEmpty
            ? _capitalize(crop)
            : '${_capitalize(crop)} · $stage';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF16A34A), Color(0xFF10B981)],
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: AppTokens.primary.withValues(alpha: 0.32),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.psychology_rounded,
              color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Farm Advisory',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  color: AppTokens.slate900,
                  letterSpacing: -0.8,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.slate500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────── Selection + action ──

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({required this.controller});

  final StationDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final timeline = controller.advisoryTimeline;
    final sown = controller.advisorySowingDate;
    final ready = controller.canRequestAdvisory;
    final loading = controller.isLoadingAdvisory;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BUILD YOUR ADVISORY', style: _labelStyle(size: 10)),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > 520;
              final cropBtn = _SelectorButton(
                icon: Icons.grass_rounded,
                label: 'CROP',
                value: timeline?.crop ?? 'Choose crop',
                placeholder: timeline == null,
                onTap: () => _openCropPicker(context, controller),
              );
              final dateBtn = _SelectorButton(
                icon: Icons.event_rounded,
                label: 'SOWN ON',
                value: sown == null ? 'Choose date' : _formatDate(sown),
                placeholder: sown == null,
                onTap: () => _pickSowingDate(context, controller),
              );
              if (wide) {
                return Row(children: [
                  Expanded(child: cropBtn),
                  const SizedBox(width: 10),
                  Expanded(child: dateBtn),
                ]);
              }
              return Column(children: [
                cropBtn,
                const SizedBox(height: 10),
                dateBtn,
              ]);
            },
          ),
          const SizedBox(height: 12),
          _LanguageToggleRow(controller: controller),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (!ready || loading)
                  ? null
                  : () => controller.refreshSoilWeatherAdvisory(),
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.psychology_rounded, size: 20),
              label: Text(loading ? 'Getting decision…' : 'Get Decision'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTokens.primary,
                disabledBackgroundColor: AppTokens.slate300,
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                minimumSize: const Size(0, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 14, color: AppTokens.slate500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Latest reading is taken from the selected crop for accurate results.',
                  style: _bodyStyle(size: 11.5, color: AppTokens.slate500),
                ),
              ),
            ],
          ),
          if (!ready) ...[
            const SizedBox(height: 8),
            Text(
              'Choose a crop and sowing date to continue.',
              style: _bodyStyle(size: 12, color: AppTokens.slate500),
            ),
          ],
        ],
      ),
    );
  }
}

class _LanguageToggleRow extends StatelessWidget {
  const _LanguageToggleRow({required this.controller});

  final StationDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final lang = controller.advisoryLanguage;
    Widget option(String code, String label) {
      final selected = lang == code;
      return Expanded(
        child: GestureDetector(
          onTap: controller.isLoadingAdvisory
              ? null
              : () => controller.setAdvisoryLanguage(code),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppTokens.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: selected ? Colors.white : AppTokens.slate500,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        const Icon(Icons.translate_rounded, size: 18, color: AppTokens.primary),
        const SizedBox(width: 10),
        Text('Language', style: _labelStyle(size: 11)),
        const Spacer(),
        Container(
          width: 168,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              option('en', 'English'),
              option('ur', 'اردو'),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTokens.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.spa_rounded,
                color: AppTokens.primary, size: 28),
          ),
          const SizedBox(height: 12),
          Text('No advisory yet', style: _sectionTitleStyle(size: 17)),
          const SizedBox(height: 6),
          Text(
            'Choose your crop, enter the sowing date, pick a language, then tap '
            '“Get Decision” to build the soil & weather advisory for this field.',
            textAlign: TextAlign.center,
            style: _bodyStyle(size: 13, color: AppTokens.slate500),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────── Summary (hero) ──

class _SummaryHero extends StatelessWidget {
  const _SummaryHero({required this.advisory, required this.rtl});

  final SoilWeatherAdvisory advisory;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    // The most severe section drives the hero tint.
    final color = _worstSeverityColor(advisory);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            rtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.tips_and_updates_rounded,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      rtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Text("TODAY'S ADVISORY",
                        style: _labelStyle(size: 9.5, color: color)),
                    const SizedBox(height: 5),
                    Text(
                      advisory.stage.isEmpty
                          ? _capitalize(advisory.cropName)
                          : '${_capitalize(advisory.cropName)} · ${advisory.stage} · Day ${advisory.das}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppTokens.slate900,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          _paragraph(advisory.summary, rtl, size: 14),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── Special focus ──

class _SpecialFocusCard extends StatelessWidget {
  const _SpecialFocusCard({required this.advisory, required this.rtl});

  final SoilWeatherAdvisory advisory;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment:
            rtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            children: [
              const Icon(Icons.priority_high_rounded,
                  color: AppTokens.alert, size: 20),
              const SizedBox(width: 8),
              Text('Focus on these', style: _sectionTitleStyle()),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in advisory.specialFocus)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTokens.alert.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTokens.alert.withValues(alpha: 0.18)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  children: [
                    const Icon(Icons.flag_rounded,
                        color: AppTokens.alert, size: 16),
                    const SizedBox(width: 9),
                    Expanded(child: _paragraph(item, rtl, size: 12.5)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────── Action points ──

class _ActionPointsCard extends StatelessWidget {
  const _ActionPointsCard({required this.advisory, required this.rtl});

  final SoilWeatherAdvisory advisory;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    final items = advisory.actionPoints;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment:
            rtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            children: [
              const Icon(Icons.checklist_rounded,
                  color: AppTokens.primary, size: 21),
              const SizedBox(width: 8),
              Text('What to do', style: _sectionTitleStyle()),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTokens.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${items.length}',
                    style: _labelStyle(size: 11, color: AppTokens.primary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTokens.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Text('${i + 1}',
                        style: _labelStyle(size: 10, color: AppTokens.primary)),
                  ),
                  const SizedBox(width: 11),
                  Expanded(child: _paragraph(items[i], rtl, size: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────── Narrative sections ──

class _SectionsCard extends StatelessWidget {
  const _SectionsCard({required this.advisory, required this.rtl});

  final SoilWeatherAdvisory advisory;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_rounded,
                  color: AppTokens.slate700, size: 20),
              const SizedBox(width: 8),
              Text('Field notes', style: _sectionTitleStyle()),
            ],
          ),
          const SizedBox(height: 6),
          for (final section in advisory.sections)
            _SectionRow(section: section, rtl: rtl),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.section, required this.rtl});

  final AdvisorySection section;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(section.severity);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment:
            rtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  section.title,
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  textAlign: rtl ? TextAlign.right : TextAlign.left,
                  style: rtl
                      ? _urduTextStyle(
                          size: 13.5,
                          color: AppTokens.slate900,
                          weight: FontWeight.w900,
                          height: 1.6,
                        )
                      : GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: AppTokens.slate900,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              _SeverityPill(severity: section.severity),
            ],
          ),
          const SizedBox(height: 7),
          _paragraph(section.description, rtl, size: 12.5),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── Signals ──

class _SignalsCard extends StatelessWidget {
  const _SignalsCard({
    required this.title,
    required this.icon,
    required this.signals,
    required this.rtl,
  });

  final String title;
  final IconData icon;
  final List<SignalReading> signals;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTokens.slate700, size: 20),
              const SizedBox(width: 8),
              Text(title, style: _sectionTitleStyle()),
            ],
          ),

          const SizedBox(height: 10),
          for (final signal in signals)
            _SignalTile(signal: signal, rtl: rtl),
        ],
      ),
    );
  }
}

class _SignalTile extends StatelessWidget {
  const _SignalTile({required this.signal, required this.rtl});

  final SignalReading signal;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(signal.status);
    final valueText = signal.value == null
        ? '—'
        : '${_trimNum(signal.value!)}${signal.unit.isEmpty ? '' : ' ${signal.unit}'}';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment:
            rtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Expanded(
                child: Text(
                  signal.label,
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  textAlign: rtl ? TextAlign.right : TextAlign.left,
                  style: rtl
                      ? _urduTextStyle(
                          size: 13.5,
                          color: AppTokens.slate900,
                          weight: FontWeight.w900,
                          height: 1.6,
                        )
                      : GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: AppTokens.slate900,
                        ),
                ),
              ),
              Text(
                valueText,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(status: signal.status),
            ],
          ),
          if (signal.expected != null && signal.value != null) ...[
            const SizedBox(height: 10),
            _RangeBar(
              value: signal.value!,
              band: signal.expected!,
              color: color,
            ),
          ],
          if (signal.message.isNotEmpty) ...[
            const SizedBox(height: 9),
            _paragraph(signal.message, rtl, size: 12, color: AppTokens.slate500),
          ],

        ],
      ),
    );
  }
}

/// A horizontal band showing the optimal range (green) inside the wider
/// warning/critical span, with a marker at the current value.
class _RangeBar extends StatelessWidget {
  const _RangeBar({
    required this.value,
    required this.band,
    required this.color,
  });

  final double value;
  final ExpectedBand band;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final lows = <double>[
      if (band.criticalLow != null) band.criticalLow!,
      if (band.warningLow != null) band.warningLow!,
      if (band.optimalLow != null) band.optimalLow!,
      value,
    ];
    final highs = <double>[
      if (band.criticalHigh != null) band.criticalHigh!,
      if (band.warningHigh != null) band.warningHigh!,
      if (band.optimalHigh != null) band.optimalHigh!,
      value,
    ];
    if (lows.isEmpty || highs.isEmpty) return const SizedBox.shrink();
    var minV = lows.reduce(math.min);
    var maxV = highs.reduce(math.max);
    final span = (maxV - minV).abs();
    final pad = span == 0 ? 1.0 : span * 0.08;
    minV -= pad;
    maxV += pad;
    final range = (maxV - minV) == 0 ? 1.0 : (maxV - minV);

    double frac(double v) => ((v - minV) / range).clamp(0.0, 1.0);

    final optLo = band.optimalLow;
    final optHi = band.optimalHigh;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final optLeft = optLo == null ? 0.0 : frac(optLo) * w;
        final optWidth =
            (optLo == null || optHi == null) ? 0.0 : (frac(optHi) - frac(optLo)) * w;
        final markerLeft = (frac(value) * w).clamp(0.0, w - 2);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 16,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // base track (warning/critical span)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 5,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8EDF3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  // optimal band
                  if (optWidth > 0)
                    Positioned(
                      left: optLeft,
                      top: 5,
                      child: Container(
                        height: 6,
                        width: optWidth,
                        decoration: BoxDecoration(
                          color: AppTokens.primary.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  // value marker
                  Positioned(
                    left: markerLeft,
                    top: 0,
                    child: Container(
                      width: 4,
                      height: 16,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (optLo != null && optHi != null) ...[
              const SizedBox(height: 5),
              Text(
                'Good band: ${_trimNum(optLo)}–${_trimNum(optHi)}',
                style: _labelStyle(size: 9, color: AppTokens.slate500),
              ),
            ],
          ],
        );
      },
    );
  }
}



// ──────────────────────────────────────────────────────────── Small pieces ──

class _SelectorButton extends StatelessWidget {
  const _SelectorButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  /// When true the value is styled as an unfilled placeholder hint.
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FB),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: placeholder
                ? AppTokens.primary.withValues(alpha: 0.35)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: AppTokens.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: _labelStyle(size: 9)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: placeholder
                          ? AppTokens.slate400
                          : AppTokens.slate900,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.unfold_more_rounded,
                size: 18, color: AppTokens.slate400),
          ],
        ),
      ),
    );
  }
}



class _SeverityPill extends StatelessWidget {
  const _SeverityPill({required this.severity});

  final String severity;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(_severityWord(severity),
          style: _labelStyle(size: 8, color: color)),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    if (status.isEmpty) return const SizedBox.shrink();
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(status.replaceAll('_', ' ').toUpperCase(),
          style: _labelStyle(size: 8, color: color)),
    );
  }
}

class _PulseIcon extends StatefulWidget {
  const _PulseIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        duration: const Duration(milliseconds: 1600), vsync: this)
      ..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.10 + _pulse.value * 0.22),
              blurRadius: 12 + _pulse.value * 10,
            ),
          ],
        ),
        child: Icon(widget.icon, color: widget.color, size: 26),
      ),
    );
  }
}

class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.child, required this.size});

  final Widget child;
  final double size;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        duration: const Duration(milliseconds: 1800), vsync: this)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              final v = Curves.easeOut.transform(_ctrl.value);
              return Transform.scale(
                scale: 1 + v * 1.1,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTokens.primary.withValues(alpha: 0.32 * (1 - v)),
                  ),
                ),
              );
            },
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _LoadingDssCard extends StatelessWidget {
  const _LoadingDssCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text('Building your soil & weather advisory…',
                style: _bodyStyle()),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTokens.alert, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Could not load the advisory',
                    style: _sectionTitleStyle(size: 15)),
                const SizedBox(height: 4),
                Text(message, style: _bodyStyle(color: AppTokens.slate500)),
                const SizedBox(height: 4),
                Text('Pull down to try again.',
                    style: _bodyStyle(size: 12, color: AppTokens.slate500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────── Pickers / sheets ──

void _openCropPicker(
    BuildContext context, StationDashboardController controller) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => _CropPickerSheet(controller: controller),
  );
}

class _CropPickerSheet extends StatefulWidget {
  const _CropPickerSheet({required this.controller});

  final StationDashboardController controller;

  @override
  State<_CropPickerSheet> createState() => _CropPickerSheetState();
}

class _CropPickerSheetState extends State<_CropPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = widget.controller.cropTimelines;
    final filtered = _query.isEmpty
        ? all
        : all
            .where((t) => t.crop.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTokens.slate300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('Pick your crop', style: _sectionTitleStyle()),
                  const Spacer(),
                  Text('${all.length} crops', style: _labelStyle()),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search crops…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: const Color(0xFFF6F8FB),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final t = filtered[i];
                    final selected = t.id == widget.controller.advisoryCropId;
                    return InkWell(
                      borderRadius: BorderRadius.circular(13),
                      onTap: () {
                        widget.controller.setAdvisoryCrop(t.id);
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTokens.primary.withValues(alpha: 0.08)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: selected
                                ? AppTokens.primary.withValues(alpha: 0.4)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color:
                                    AppTokens.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.grass_rounded,
                                  color: AppTokens.primary, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.crop,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w900,
                                      color: AppTokens.slate900,
                                    ),
                                  ),
                                  Text(
                                    '${t.stages.length} stages · ${t.totalDays} day cycle · sow ${t.sowWindow}',
                                    style: _bodyStyle(
                                        size: 11.5, color: AppTokens.slate500),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              const Icon(Icons.check_circle_rounded,
                                  color: AppTokens.primary, size: 22),
                          ],
                        ),
                      ),
                    );
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

Future<void> _pickSowingDate(
    BuildContext context, StationDashboardController controller) async {
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: controller.advisorySowingDate ?? now,
    firstDate: now.subtract(const Duration(days: 400)),
    lastDate: now,
    helpText: 'When did you sow this crop?',
    confirmText: 'SET DATE',
    cancelText: 'CANCEL',
    fieldLabelText: 'Sowing date',
    initialEntryMode: DatePickerEntryMode.calendarOnly,
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: AppTokens.primary,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: AppTokens.slate900,
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          headerBackgroundColor: AppTokens.primary,
          headerForegroundColor: Colors.white,
          elevation: 8,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          todayBorder: const BorderSide(color: AppTokens.primary, width: 1.4),
          dayShape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppTokens.primary,
            textStyle: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
        ),
      ),
      child: child!,
    ),
  );
  if (picked != null) {
    controller.setAdvisorySowingDate(picked);
  }
}

// ──────────────────────────────────────────────────────────────── Helpers ──

TextStyle _urduTextStyle({
  required double size,
  required Color color,
  FontWeight weight = FontWeight.w700,
  double height = 1.8,
}) {
  return TextStyle(
    fontFamily: 'Jameel Noori Nastaleeq',
    fontFamilyFallback: [
      'Jameel Noori',
      'JameelNoori',
      'Jameel Noori Nastaleeq Kasheeda',
      GoogleFonts.notoNastaliqUrdu().fontFamily!,
      GoogleFonts.notoSansArabic().fontFamily!,
    ],
    fontSize: size + 4.0,
    fontWeight: weight == FontWeight.w900 ? FontWeight.w800 : weight,
    color: color,
    height: height,
  );
}

TextStyle _sectionTitleStyle({double size = 19, bool rtl = false}) {
  if (rtl) {
    return _urduTextStyle(size: size, color: AppTokens.slate900, weight: FontWeight.w900, height: 1.6);
  }
  return GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: FontWeight.w900,
    color: AppTokens.slate900,
    letterSpacing: -0.5,
  );
}

TextStyle _bodyStyle({
  double size = 13,
  Color color = AppTokens.slate700,
  bool rtl = false,
  FontWeight weight = FontWeight.w700,
}) {
  if (rtl) {
    return _urduTextStyle(size: size, color: color, weight: weight, height: 1.8);
  }
  return GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.45,
  );
}

/// A paragraph of advisory text, direction-aware so Urdu renders right-to-left.
Widget _paragraph(String text, bool rtl,
    {double size = 13, Color color = AppTokens.slate700}) {
  return Text(
    text,
    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    textAlign: rtl ? TextAlign.right : TextAlign.left,
    style: _bodyStyle(size: size, color: color, rtl: rtl),
  );
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

String _trimNum(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(1);
}

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0xFFE8EDF3)),
    boxShadow: [
      BoxShadow(
        color: AppTokens.slate900.withValues(alpha: 0.04),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

TextStyle _labelStyle({double size = 10, Color color = AppTokens.slate500}) {
  return GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: FontWeight.w900,
    color: color,
    letterSpacing: 0.8,
  );
}


// Severity → traffic-light colour (advisory sections / findings).
Color _severityColor(String severity) {
  switch (severity.toLowerCase()) {
    case 'critical':
      return AppTokens.alert;
    case 'warning':
      return const Color(0xFFF97316); // orange
    case 'watch':
      return AppTokens.caution;
    case 'info':
    case 'ok':
    case 'good':
      return AppTokens.primary;
    default:
      return AppTokens.slate500;
  }
}

String _severityWord(String severity) {
  switch (severity.toLowerCase()) {
    case 'critical':
      return 'ACT NOW';
    case 'warning':
      return 'ACT';
    case 'watch':
      return 'WATCH';
    case 'info':
    case 'ok':
    case 'good':
      return 'OK';
    default:
      return severity.toUpperCase();
  }
}

// Signal status → colour (optimal / high / low / very_high …).
Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'optimal':
    case 'ok':
    case 'good':
      return AppTokens.primary;
    case 'very_high':
    case 'very_low':
      return AppTokens.alert;
    case 'high':
    case 'low':
      return AppTokens.caution;
    case 'none':
      return AppTokens.slate400;
    default:
      return AppTokens.slate500;
  }
}

// Pick the hero tint from the most severe section/finding.
Color _worstSeverityColor(SoilWeatherAdvisory advisory) {
  var rank = 0;
  int rankOf(String s) {
    switch (s.toLowerCase()) {
      case 'critical':
        return 3;
      case 'warning':
        return 2;
      case 'watch':
        return 1;
      default:
        return 0;
    }
  }

  for (final s in advisory.sections) {
    rank = math.max(rank, rankOf(s.severity));
  }
  for (final f in advisory.findings) {
    rank = math.max(rank, rankOf(f.severity));
  }
  switch (rank) {
    case 3:
      return AppTokens.alert;
    case 2:
      return const Color(0xFFF97316);
    case 1:
      return AppTokens.caution;
    default:
      return AppTokens.primary;
  }
}

// Logical stage-icon key -> Material icon.
IconData stageIcon(String key) {
  switch (key) {
    case 'sprout':
      return Icons.eco_rounded;
    case 'leaf':
      return Icons.grass_rounded;
    case 'stem':
      return Icons.park_rounded;
    case 'flower':
      return Icons.local_florist_rounded;
    case 'pod':
      return Icons.spa_rounded;
    case 'grain':
      return Icons.grain_rounded;
    case 'harvest':
      return Icons.agriculture_rounded;
    default:
      return Icons.energy_savings_leaf_rounded;
  }
}


