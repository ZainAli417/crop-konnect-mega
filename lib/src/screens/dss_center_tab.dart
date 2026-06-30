import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/dashboard_theme.dart';
import '../models/crop_timeline.dart';
import '../models/dss.dart';
import '../models/sensor_reading.dart';
import '../viewmodels/station_dashboard_controller.dart';

// ════════════════════════════════════════════════════════════════════════════
//  DSS Center
//  Pick a crop + sowing date → the growth stage is computed automatically and
//  drawn on an animated stage timeline. Every decision card compares live
//  sensors against the crop's exact needs at that stage and states the call
//  plainly, with a score.
// ════════════════════════════════════════════════════════════════════════════

class DssCenterTab extends StatelessWidget {
  const DssCenterTab({super.key, required this.controller});

  final StationDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final analysis = controller.dssAnalysis;
        return RefreshIndicator(
          onRefresh: controller.refreshDss,
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
                _Header(analysis: analysis),
                const SizedBox(height: 14),
                _StageTimelineCard(controller: controller),
                const SizedBox(height: 14),
                if (controller.dssErrorMessage != null)
                  _ErrorCard(message: controller.dssErrorMessage!)
                else if (analysis == null)
                  const _LoadingDssCard()
                else ...[
                  _FarmerActionHero(
                    analysis: analysis,
                    reading: controller.latestReading,
                  ),
                  const SizedBox(height: 14),
                  _DssLastReadingCard(reading: controller.latestReading),
                  const SizedBox(height: 14),
                  _FieldScoreCard(analysis: analysis),
                  const SizedBox(height: 14),
                  _PriorityActions(analysis: analysis),
                  const SizedBox(height: 14),
                  _ModuleGrid(analysis: analysis),
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
  const _Header({required this.analysis});

  final DssAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final current = analysis;
    final subtitle = current == null
        ? 'Building your field advisory'
        : '${current.crop.name} · ${current.stage.name}';
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

// ───────────────────────────────────────────────── Stage timeline (hero) ──

class _StageTimelineCard extends StatelessWidget {
  const _StageTimelineCard({required this.controller});

  final StationDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final timeline = controller.activeTimeline;
    if (timeline == null) {
      return const _LoadingDssCard();
    }
    final das = controller.daysAfterSowing;
    final stageIndex = controller.currentStageIndex;
    final stage = timeline.stages[stageIndex];
    final past = controller.isPastHarvest;
    final daysLeft = (stage.endDay - das).clamp(0, 100000);
    final nextStage = stageIndex + 1 < timeline.stages.length
        ? timeline.stages[stageIndex + 1]
        : null;

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Selector row: crop + sowing date ──────────────────────────
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth > 520;
                final cropBtn = _SelectorButton(
                  icon: Icons.grass_rounded,
                  label: 'CROP',
                  value: timeline.crop,
                  onTap: () => _openCropPicker(context, controller),
                );
                final dateBtn = _SelectorButton(
                  icon: Icons.event_rounded,
                  label: 'SOWN ON',
                  value: _formatDate(controller.sowingDate),
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
            const SizedBox(height: 18),

            // ── Current stage headline ────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _PulseIcon(
                  icon: stageIcon(stage.icon),
                  color: AppTokens.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              stage.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: AppTokens.slate900,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _SensitivityTag(sensitivity: stage.sensitivity),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        past
                            ? 'Day $das · cycle complete (${timeline.totalDays} days)'
                            : 'Day $das of ${timeline.totalDays}'
                                '${daysLeft > 0 ? '  ·  $daysLeft days left in stage' : '  ·  moving to next stage'}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── The animated stage bar ────────────────────────────────────
            _StageBar(
              timeline: timeline,
              das: das,
              currentIndex: stageIndex,
            ),

            const SizedBox(height: 14),

            // ── Focus line ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTokens.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.flag_rounded,
                      color: AppTokens.primary, size: 18),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('FOCUS NOW',
                            style:
                                _labelStyle(size: 9, color: AppTokens.primary)),
                        const SizedBox(height: 3),
                        Text(stage.focus, style: _bodyStyle(size: 12.5)),
                        if (nextStage != null && !past) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Next: ${nextStage.name} in $daysLeft days',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppTokens.slate700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The proportional, animated stage bar with per-stage icon pins.
class _StageBar extends StatelessWidget {
  const _StageBar({
    required this.timeline,
    required this.das,
    required this.currentIndex,
  });

  final CropTimeline timeline;
  final int das;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final stages = timeline.stages;
    final total = timeline.totalDays.toDouble().clamp(1, 100000).toDouble();
    final progress = (das / total).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        const trackH = 12.0;
        const pin = 30.0;
        // Draw non-current pins first, then the current pin on top so it is
        // never hidden by a neighbouring short stage.
        final pins = <Widget>[];
        for (var i = 0; i < stages.length; i++) {
          if (i != currentIndex) pins.add(_stagePin(i, stages[i], w, pin));
        }
        if (currentIndex < stages.length) {
          pins.add(_stagePin(currentIndex, stages[currentIndex], w, pin));
        }
        return SizedBox(
          height: pin + 16,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // base track
              Positioned(
                left: 0,
                right: 0,
                top: pin / 2 - trackH / 2,
                child: Container(
                  height: trackH,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EDF3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              // progress fill
              Positioned(
                left: 0,
                top: pin / 2 - trackH / 2,
                child: Container(
                  height: trackH,
                  width: w * progress,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF16A34A), Color(0xFF34D399)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              // stage pins (icons) sit on top of the loader fill
              ...pins,
            ],
          ),
        );
      },
    );
  }

  Widget _stagePin(int i, TimelineStage s, double w, double pin) {
    final total = timeline.totalDays <= 0 ? 1 : timeline.totalDays;
    final mid = ((s.startDay + s.endDay) / 2) / total;
    final maxLeft = w > pin ? w - pin : 0.0;
    final left = ((w * mid.clamp(0.0, 1.0)) - pin / 2).clamp(0.0, maxLeft);
    final passed = i < currentIndex;
    final current = i == currentIndex;
    final color = current
        ? AppTokens.primary
        : passed
            ? const Color(0xFF34D399)
            : AppTokens.slate400;
    final bg = current
        ? AppTokens.primary
        : passed
            ? Colors.white
            : const Color(0xFFEDF1F6);
    final fg = current ? Colors.white : color;

    return Positioned(
      left: left,
      top: 0,
      child: current
          ? _PulseRing(
              size: pin, child: _pinBody(s, pin, bg, fg, color, current))
          : _pinBody(s, pin, bg, fg, color, current),
    );
  }

  Widget _pinBody(TimelineStage s, double pin, Color bg, Color fg, Color border,
      bool current) {
    return Container(
      width: pin,
      height: pin,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: current ? 0 : 2),
        boxShadow: current
            ? [
                BoxShadow(
                  color: AppTokens.primary.withValues(alpha: 0.45),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Icon(stageIcon(s.icon), size: 17, color: fg),
    );
  }
}

// ───────────────────────────────────────────────────────── Farmer action ──

class _FarmerActionHero extends StatelessWidget {
  const _FarmerActionHero({required this.analysis, required this.reading});

  final DssAnalysis analysis;
  final SensorReading? reading;

  @override
  Widget build(BuildContext context) {
    final recommendation = analysis.priorityRecommendations.isNotEmpty
        ? analysis.priorityRecommendations.first
        : null;
    final color = recommendation == null
        ? AppTokens.primary
        : _urgencyColor(recommendation.urgency);
    final icon = recommendation == null
        ? Icons.check_circle_rounded
        : _urgencyIcon(recommendation.urgency);
    final title = recommendation?.title ?? 'Field is on track';
    final action = recommendation?.farmerAction ??
        'Keep the station running and walk the field once today.';
    final check = recommendation?.fieldCheck ??
        'Check for dry patches, weak plants, standing water, or pest signs.';

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 29),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TODAY ON FIELD',
                        style: _labelStyle(size: 9.5, color: color)),
                    const SizedBox(height: 5),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppTokens.slate900,
                        letterSpacing: -0.55,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${analysis.crop.name} · ${analysis.stage.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _bodyStyle(size: 12, color: AppTokens.slate500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _DssActionLine(
            icon: Icons.task_alt_rounded,
            label: 'Do',
            text: action,
            color: color,
          ),
          const SizedBox(height: 9),
          _DssActionLine(
            icon: Icons.search_rounded,
            label: 'Check',
            text: check,
            color: AppTokens.slate700,
          ),
          if (reading != null) ...[
            const SizedBox(height: 12),
            Text(
              'Based on last reading: ${_dssReadingAge(reading!.recordedAt)}',
              style: _bodyStyle(size: 11.5, color: AppTokens.slate500),
            ),
          ],
          if (recommendation != null) ...[
            const SizedBox(height: 13),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () =>
                    _showRecommendationSheet(context, recommendation),
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text('See sensor proof'),
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  textStyle: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DssActionLine extends StatelessWidget {
  const _DssActionLine({
    required this.icon,
    required this.label,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 9),
        SizedBox(
          width: 48,
          child: Text(label.toUpperCase(),
              style: _labelStyle(size: 9.5, color: color)),
        ),
        Expanded(
          child: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: _bodyStyle(size: 13.5, color: AppTokens.slate700),
          ),
        ),
      ],
    );
  }
}

class _DssLastReadingCard extends StatelessWidget {
  const _DssLastReadingCard({required this.reading});

  final SensorReading? reading;

  @override
  Widget build(BuildContext context) {
    final r = reading;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sensors_rounded,
                  color: AppTokens.primary, size: 19),
              const SizedBox(width: 8),
              Text('Last Reading', style: _sectionTitleStyle(size: 16)),
              const Spacer(),
              Text(
                r == null ? 'No data yet' : _dssShortDateTime(r.recordedAt),
                style: _labelStyle(size: 9.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final chips = <Widget>[
                _DssReadingChip(
                  icon: Icons.water_drop_rounded,
                  label: 'Moisture',
                  value: formatMetric(r?.moist, suffix: '%'),
                  color: AppTokens.primary,
                ),
                _DssReadingChip(
                  icon: Icons.thermostat_rounded,
                  label: 'Temp',
                  value: formatMetric(r?.temp, suffix: '°C'),
                  color: AppTokens.caution,
                ),
                _DssReadingChip(
                  icon: Icons.grain_rounded,
                  label: 'Rain',
                  value: formatMetric(r?.rain, suffix: 'mm'),
                  color: AppTokens.info,
                ),
                _DssReadingChip(
                  icon: Icons.air_rounded,
                  label: 'Wind',
                  value: formatMetric(r?.ws, suffix: 'm/s'),
                  color: AppTokens.slate700,
                ),
              ];
              if (c.maxWidth < 560) {
                return Wrap(spacing: 8, runSpacing: 8, children: chips);
              }
              return Row(
                children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    Expanded(child: chips[i]),
                    if (i < chips.length - 1) const SizedBox(width: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DssReadingChip extends StatelessWidget {
  const _DssReadingChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EDF3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _labelStyle(size: 8.5)),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppTokens.slate900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── Field score ──

class _FieldScoreCard extends StatelessWidget {
  const _FieldScoreCard({required this.analysis});

  final DssAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(analysis.fieldScore.value);
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final scoreBlock =
                _ScoreDial(value: analysis.fieldScore.value, color: color);
            final textBlock = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('FIELD STATUS', style: _labelStyle()),
                const SizedBox(height: 8),
                Text(
                  analysis.fieldScore.label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: compact ? 24 : 30,
                    fontWeight: FontWeight.w900,
                    color: AppTokens.slate900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(analysis.fieldScore.summary, style: _bodyStyle()),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                        icon: Icons.grass_rounded,
                        label: analysis.crop.group.replaceAll('_', ' ')),
                    _InfoChip(
                      icon: Icons.calendar_month_rounded,
                      label: analysis.crop.seasons.isEmpty
                          ? 'season guide'
                          : analysis.crop.seasons.join(', '),
                    ),
                    _InfoChip(
                      icon: Icons.place_rounded,
                      label: analysis.crop.pakistanRegions.isEmpty
                          ? 'Pakistan baseline'
                          : analysis.crop.pakistanRegions.take(2).join(', '),
                    ),
                  ],
                ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [scoreBlock, const SizedBox(height: 16), textBlock],
              );
            }
            return Row(
              children: [
                scoreBlock,
                const SizedBox(width: 24),
                Expanded(child: textBlock)
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PriorityActions extends StatelessWidget {
  const _PriorityActions({required this.analysis});

  final DssAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final items = analysis.priorityRecommendations.length <= 1
        ? const <DssRecommendation>[]
        : analysis.priorityRecommendations.skip(1).toList(growable: false);
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.playlist_add_check_rounded,
                    color: AppTokens.caution, size: 22),
                const SizedBox(width: 8),
                Text('Next checks', style: _sectionTitleStyle()),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              items.isEmpty
                  ? 'No extra jobs. Keep walking the field and watching fresh readings.'
                  : 'After the main job, check these before spending on routine work.',
              style: _bodyStyle(color: AppTokens.slate500),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const _EmptyAction()
            else
              // On wide screens lay the priority actions out side by side.
              LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth >= 900
                    ? 3
                    : c.maxWidth >= 600
                        ? 2
                        : 1;
                if (cols == 1) {
                  return Column(
                    children: items
                        .map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _RecommendationTile(recommendation: e),
                            ))
                        .toList(),
                  );
                }
                final gap = 10.0;
                final width = (c.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: items
                      .map((e) => SizedBox(
                          width: width,
                          child: _RecommendationTile(recommendation: e)))
                      .toList(),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _ModuleGrid extends StatelessWidget {
  const _ModuleGrid({required this.analysis});

  final DssAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide, short cards: fill big screens with more columns, never tall.
        final w = constraints.maxWidth;
        final columns = w >= 1500
            ? 5
            : w >= 1150
                ? 4
                : w >= 820
                    ? 3
                    : w >= 540
                        ? 2
                        : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - (gap * (columns - 1))) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dashboard_customize_rounded,
                    color: AppTokens.slate700, size: 20),
                const SizedBox(width: 8),
                Text('More field checks', style: _sectionTitleStyle()),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTokens.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${analysis.modules.length}',
                      style: _labelStyle(size: 11, color: AppTokens.primary)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final module in analysis.modules)
                  SizedBox(
                    width: width,
                    child: RepaintBoundary(child: _ModuleCard(module: module)),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// A wide, short decision card carrying a score.
class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final DssModuleResult module;

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(module.score);
    final hasActions = module.recommendations.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: hasActions ? () => _showModuleSheet(context, module) : null,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_moduleIcon(module.id), color: color, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        module.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: AppTokens.slate900,
                        ),
                      ),
                      Text(
                        module.status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                _ScoreChip(score: module.score, color: color),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: module.score / 100,
                minHeight: 6,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              module.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _bodyStyle(size: 12, color: AppTokens.slate500),
            ),
            if (hasActions) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(_urgencyIcon(module.recommendations.first.urgency),
                      size: 13,
                      color:
                          _urgencyColor(module.recommendations.first.urgency)),
                  const SizedBox(width: 5),
                  Text(
                    '${module.recommendations.length} action${module.recommendations.length == 1 ? '' : 's'} · tap',
                    style: _labelStyle(
                        size: 10,
                        color: _urgencyColor(
                            module.recommendations.first.urgency)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  const _RecommendationTile({required this.recommendation});

  final DssRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final color = _urgencyColor(recommendation.urgency);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showRecommendationSheet(context, recommendation),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_urgencyIcon(recommendation.urgency),
                    color: color, size: 20),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    recommendation.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: AppTokens.slate900,
                      height: 1.25,
                    ),
                  ),
                ),
                _UrgencyPill(urgency: recommendation.urgency),
              ],
            ),
            const SizedBox(height: 7),
            Text(recommendation.decision, style: _bodyStyle(size: 12.5)),
            const SizedBox(height: 6),
            Text(
              recommendation.farmerAction,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: _bodyStyle(size: 12, color: AppTokens.slate500),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectorButton extends StatelessWidget {
  const _SelectorButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

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
          border: Border.all(color: const Color(0xFFE2E8F0)),
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
                      color: AppTokens.slate900,
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

class _SensitivityTag extends StatelessWidget {
  const _SensitivityTag({required this.sensitivity});

  final String sensitivity;

  @override
  Widget build(BuildContext context) {
    final color = sensitivity == 'high'
        ? AppTokens.alert
        : sensitivity == 'low'
            ? AppTokens.primary
            : AppTokens.caution;
    final label = sensitivity == 'high'
        ? 'KEY STAGE'
        : sensitivity == 'low'
            ? 'HARDY'
            : 'STEADY';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(label, style: _labelStyle(size: 8.5, color: color)),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.score, required this.color});

  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$score',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
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

// Ripple drawn behind the current stage pin. The outer box stays exactly the
// pin size so the pin never shifts off the line — only the ripple scales out.
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
          // ripple — scaled (no layout impact), so the pin stays anchored
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

class _ScoreDial extends StatelessWidget {
  const _ScoreDial({required this.value, required this.color});

  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      height: 128,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 128,
            height: 128,
            child: CircularProgressIndicator(
              value: value / 100,
              strokeWidth: 12,
              color: color,
              backgroundColor: color.withValues(alpha: 0.12),
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$value',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: -1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text('/ 100', style: _labelStyle(size: 9, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTokens.slate500),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTokens.slate700,
            ),
          ),
        ],
      ),
    );
  }
}

class _UrgencyPill extends StatelessWidget {
  const _UrgencyPill({required this.urgency});

  final DssUrgency urgency;

  @override
  Widget build(BuildContext context) {
    final color = _urgencyColor(urgency);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(_urgencyLabel(urgency),
          style: _labelStyle(size: 8, color: color)),
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
            child: Text('Loading crop stages and building your advisory…',
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
              child: Text(message, style: _bodyStyle(color: AppTokens.alert))),
        ],
      ),
    );
  }
}

class _EmptyAction extends StatelessWidget {
  const _EmptyAction();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTokens.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppTokens.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Field is on track. Keep the station running and check back through the day.',
              style: _bodyStyle(),
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
                    final selected = t.id == widget.controller.selectedCropId;
                    return InkWell(
                      borderRadius: BorderRadius.circular(13),
                      onTap: () {
                        widget.controller.setCrop(t.id);
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
    initialDate: controller.sowingDate,
    firstDate: now.subtract(const Duration(days: 400)),
    lastDate: now,
    helpText: 'When did you sow this crop?',
    confirmText: 'SET DATE',
    cancelText: 'CANCEL',
    fieldLabelText: 'Sowing date',
    // Classic calendar grid only — no keyboard-entry toggle.
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
    controller.setSowingDate(picked);
  }
}

void _showModuleSheet(BuildContext context, DssModuleResult module) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          final color = _scoreColor(module.score);
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(_moduleIcon(module.id), color: color, size: 21),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                      child: Text(module.title, style: _sectionTitleStyle())),
                  _ScoreChip(score: module.score, color: color),
                ],
              ),
              const SizedBox(height: 10),
              Text(module.summary, style: _bodyStyle()),
              const SizedBox(height: 16),
              if (module.recommendations.isEmpty)
                const _EmptyAction()
              else
                ...module.recommendations.map(
                  (rec) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RecommendationTile(recommendation: rec),
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}

void _showRecommendationSheet(
    BuildContext context, DssRecommendation recommendation) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: [
              Row(
                children: [
                  Icon(_urgencyIcon(recommendation.urgency),
                      color: _urgencyColor(recommendation.urgency)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(recommendation.title,
                          style: _sectionTitleStyle())),
                  _UrgencyPill(urgency: recommendation.urgency),
                ],
              ),
              const SizedBox(height: 16),
              _DetailBlock(
                  title: 'The call',
                  text: recommendation.decision,
                  icon: Icons.assistant_direction_rounded),
              _DetailBlock(
                  title: 'Why it matters',
                  text: recommendation.whyItMatters,
                  icon: Icons.info_rounded),
              _DetailBlock(
                  title: 'Do this',
                  text: recommendation.farmerAction,
                  icon: Icons.task_alt_rounded),
              _DetailBlock(
                  title: 'Check in the field',
                  text: recommendation.fieldCheck,
                  icon: Icons.search_rounded),
              const SizedBox(height: 10),
              Text('What your sensors show',
                  style: _sectionTitleStyle(size: 17)),
              const SizedBox(height: 4),
              Text(
                'Colour shows if a reading is good, worth watching, or needs action.',
                style: _bodyStyle(size: 12, color: AppTokens.slate500),
              ),
              const SizedBox(height: 10),
              ...recommendation.evidence.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _EvidenceRow(evidence: e),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock(
      {required this.title, required this.text, required this.icon});

  final String title;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppTokens.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _labelStyle()),
                  const SizedBox(height: 4),
                  Text(text, style: _bodyStyle()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// A full-width reading row: tone dot + label + plain hint + value + status word.
class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.evidence});

  final DssEvidence evidence;

  @override
  Widget build(BuildContext context) {
    final tone = evidence.tone;
    final color = _toneColor(tone);
    final word = _toneWord(tone);
    final tinted = tone != DssTone.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: tinted ? color.withValues(alpha: 0.06) : const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              tinted ? color.withValues(alpha: 0.20) : const Color(0xFFE8EDF3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  evidence.label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTokens.slate900,
                  ),
                ),
                if (evidence.note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    evidence.note,
                    style: _bodyStyle(size: 11.5, color: AppTokens.slate500),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                evidence.value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: tinted ? color : AppTokens.slate900,
                ),
              ),
              if (word.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(word, style: _labelStyle(size: 8.5, color: color)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────── Helpers ──

String _formatDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
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

TextStyle _sectionTitleStyle({double size = 19}) {
  return GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: FontWeight.w900,
    color: AppTokens.slate900,
    letterSpacing: -0.5,
  );
}

TextStyle _bodyStyle({double size = 13, Color color = AppTokens.slate700}) {
  return GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: color,
    height: 1.45,
  );
}

// Traffic-light scoring — green = good, amber = keep an eye, red = act now.
Color _scoreColor(int score) {
  if (score >= 70) return AppTokens.primary; // green
  if (score >= 50) return AppTokens.caution; // amber
  return AppTokens.alert; // red
}

Color _toneColor(DssTone tone) {
  switch (tone) {
    case DssTone.good:
      return AppTokens.primary;
    case DssTone.warn:
      return AppTokens.caution;
    case DssTone.bad:
      return AppTokens.alert;
    case DssTone.info:
      return AppTokens.slate500;
  }
}

String _toneWord(DssTone tone) {
  switch (tone) {
    case DssTone.good:
      return 'GOOD';
    case DssTone.warn:
      return 'WATCH';
    case DssTone.bad:
      return 'ACT';
    case DssTone.info:
      return '';
  }
}

Color _urgencyColor(DssUrgency urgency) {
  switch (urgency) {
    case DssUrgency.critical:
    case DssUrgency.high:
      return AppTokens.alert;
    case DssUrgency.moderate:
      return AppTokens.caution;
    case DssUrgency.low:
      return AppTokens.info;
    case DssUrgency.info:
      return AppTokens.slate500;
  }
}

String _urgencyLabel(DssUrgency urgency) {
  switch (urgency) {
    case DssUrgency.critical:
      return 'NOW';
    case DssUrgency.high:
      return 'TODAY';
    case DssUrgency.moderate:
      return 'SOON';
    case DssUrgency.low:
      return 'PLAN';
    case DssUrgency.info:
      return 'NOTE';
  }
}

String _dssShortDateTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.day}/${value.month} $hour:$minute';
}

String _dssReadingAge(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
}

IconData _urgencyIcon(DssUrgency urgency) {
  switch (urgency) {
    case DssUrgency.critical:
      return Icons.priority_high_rounded;
    case DssUrgency.high:
      return Icons.warning_amber_rounded;
    case DssUrgency.moderate:
      return Icons.error_outline_rounded;
    case DssUrgency.low:
      return Icons.info_outline_rounded;
    case DssUrgency.info:
      return Icons.tips_and_updates_outlined;
  }
}

IconData _moduleIcon(String id) {
  switch (id) {
    case 'live_data':
      return Icons.sensors_rounded;
    case 'irrigation':
      return Icons.water_drop_rounded;
    case 'crop_stress':
      return Icons.local_florist_rounded;
    case 'temperature':
      return Icons.thermostat_rounded;
    case 'soil_health':
      return Icons.terrain_rounded;
    case 'nutrients':
      return Icons.science_rounded;
    case 'ph':
      return Icons.opacity_rounded;
    case 'salinity':
      return Icons.grain_rounded;
    case 'spray':
      return Icons.air_rounded;
    case 'pest_disease':
      return Icons.pest_control_rounded;
    case 'stage':
      return Icons.timeline_rounded;
    default:
      return Icons.eco_rounded;
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
