import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/dashboard_theme.dart';
import '../models/dss.dart';
import '../viewmodels/station_dashboard_controller.dart';

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
            color: const Color(0xFFF8FAFC),
            child: ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _Header(analysis: analysis),
                const SizedBox(height: 14),
                if (controller.dssErrorMessage != null)
                  _ErrorCard(message: controller.dssErrorMessage!)
                else if (analysis == null)
                  const _LoadingDssCard()
                else ...[
                  _FieldScoreCard(analysis: analysis),
                  const SizedBox(height: 14),
                  _PriorityActions(analysis: analysis),
                  const SizedBox(height: 14),
                  _ModuleGrid(analysis: analysis),
                  const SizedBox(height: 14),
                  _SourceNote(analysis: analysis),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.analysis});

  final DssAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final currentAnalysis = analysis;
    final subtitle = currentAnalysis == null
        ? 'Preparing farmer advisory'
        : '${currentAnalysis.crop.name} - ${currentAnalysis.stage.name}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTokens.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.psychology_rounded,
            color: AppTokens.primary,
            size: 23,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DSS Center',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 26,
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
        if (currentAnalysis != null)
          _ConfidencePill(confidence: currentAnalysis.dataConfidence),
      ],
    );
  }
}

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
            final compact = constraints.maxWidth < 620;
            final scoreBlock = _ScoreDial(
              value: analysis.fieldScore.value,
              color: color,
            );
            final textBlock = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What needs attention now',
                  style: _labelStyle(),
                ),
                const SizedBox(height: 8),
                Text(
                  analysis.fieldScore.label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: compact ? 23 : 30,
                    fontWeight: FontWeight.w900,
                    color: AppTokens.slate900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  analysis.fieldScore.summary,
                  style: _bodyStyle(),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.grass_rounded,
                      label: analysis.crop.group.replaceAll('_', ' '),
                    ),
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
                children: [
                  scoreBlock,
                  const SizedBox(height: 16),
                  textBlock,
                ],
              );
            }
            return Row(
              children: [
                scoreBlock,
                const SizedBox(width: 22),
                Expanded(child: textBlock),
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
    final items = analysis.priorityRecommendations;
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Priority actions', style: _sectionTitleStyle()),
            const SizedBox(height: 4),
            Text(
              items.isEmpty
                  ? 'No urgent DSS action is raised from current readings.'
                  : 'Handle these first before routine farm work.',
              style: _bodyStyle(color: AppTokens.slate500),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const _EmptyAction()
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RecommendationTile(recommendation: item),
                ),
              ),
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
        final columns = constraints.maxWidth >= 980
            ? 3
            : constraints.maxWidth >= 640
                ? 2
                : 1;
        final gap = 12.0;
        final width = (constraints.maxWidth - (gap * (columns - 1))) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Decision modules', style: _sectionTitleStyle()),
            const SizedBox(height: 10),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final module in analysis.modules)
                  SizedBox(
                    width: width,
                    height: columns == 1 ? 170 : 214,
                    child: RepaintBoundary(
                      child: _ModuleCard(module: module),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final DssModuleResult module;

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(module.score);
    final hasActions = module.recommendations.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: hasActions
          ? () => _showModuleSheet(context, module)
          : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_moduleIcon(module.id), color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    module.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppTokens.slate900,
                    ),
                  ),
                ),
                Text(
                  '${module.score}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: module.score / 100,
                minHeight: 7,
                color: color,
                backgroundColor: color.withValues(alpha: 0.1),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              module.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                module.summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: _bodyStyle(size: 12, color: AppTokens.slate500),
              ),
            ),
            if (hasActions)
              Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  '${module.recommendations.length} action${module.recommendations.length == 1 ? '' : 's'}',
                  style: _labelStyle(color: color),
                ),
              ),
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
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_urgencyIcon(recommendation.urgency), color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          recommendation.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppTokens.slate900,
                          ),
                        ),
                      ),
                      _UrgencyPill(urgency: recommendation.urgency),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    recommendation.decision,
                    style: _bodyStyle(size: 12.5),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    recommendation.farmerAction,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _bodyStyle(size: 12, color: AppTokens.slate500),
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

class _SourceNote extends StatelessWidget {
  const _SourceNote({required this.analysis});

  final DssAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined,
              color: AppTokens.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${analysis.sourceSummary} This is advisory guidance; confirm important input decisions with field observation and local agronomy support.',
              style: _bodyStyle(size: 12, color: AppTokens.slate500),
            ),
          ),
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
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 132,
            height: 132,
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
              Text('FIELD SCORE', style: _labelStyle(size: 9, color: color)),
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

class _ConfidencePill extends StatelessWidget {
  const _ConfidencePill({required this.confidence});

  final DssConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final color = switch (confidence) {
      DssConfidence.high => AppTokens.primary,
      DssConfidence.medium => AppTokens.caution,
      DssConfidence.low => AppTokens.alert,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${confidence.name.toUpperCase()} CONFIDENCE',
        style: _labelStyle(size: 9, color: color),
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        urgency.name.toUpperCase(),
        style: _labelStyle(size: 8, color: color),
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
            child: Text(
              'Loading crop knowledge and building DSS advisory...',
              style: _bodyStyle(),
            ),
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
            child: Text(
              message,
              style: _bodyStyle(color: AppTokens.alert),
            ),
          ),
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
          const Icon(Icons.check_circle_outline_rounded,
              color: AppTokens.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Keep monitoring. No urgent farmer action is needed from the current sensor picture.',
              style: _bodyStyle(),
            ),
          ),
        ],
      ),
    );
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
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: [
              Text(module.title, style: _sectionTitleStyle()),
              const SizedBox(height: 6),
              Text(module.summary, style: _bodyStyle()),
              const SizedBox(height: 14),
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
  BuildContext context,
  DssRecommendation recommendation,
) {
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
                  Icon(
                    _urgencyIcon(recommendation.urgency),
                    color: _urgencyColor(recommendation.urgency),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      recommendation.title,
                      style: _sectionTitleStyle(),
                    ),
                  ),
                  _UrgencyPill(urgency: recommendation.urgency),
                ],
              ),
              const SizedBox(height: 16),
              _DetailBlock(
                title: 'Decision',
                text: recommendation.decision,
                icon: Icons.assistant_direction_rounded,
              ),
              _DetailBlock(
                title: 'Why this matters',
                text: recommendation.whyItMatters,
                icon: Icons.info_outline_rounded,
              ),
              _DetailBlock(
                title: 'Farmer action',
                text: recommendation.farmerAction,
                icon: Icons.task_alt_rounded,
              ),
              _DetailBlock(
                title: 'What to check in the field',
                text: recommendation.fieldCheck,
                icon: Icons.search_rounded,
              ),
              const SizedBox(height: 10),
              Text('Evidence from sensors', style: _sectionTitleStyle(size: 18)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recommendation.evidence
                    .map((evidence) => _EvidenceChip(evidence: evidence))
                    .toList(),
              ),
            ],
          );
        },
      );
    },
  );
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.title,
    required this.text,
    required this.icon,
  });

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

class _EvidenceChip extends StatelessWidget {
  const _EvidenceChip({required this.evidence});

  final DssEvidence evidence;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(evidence.label, style: _labelStyle(size: 9)),
          const SizedBox(height: 2),
          Text(
            evidence.value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppTokens.slate900,
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0xFFE2E8F0)),
    boxShadow: [
      BoxShadow(
        color: AppTokens.slate900.withValues(alpha: 0.04),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

TextStyle _labelStyle({
  double size = 10,
  Color color = AppTokens.slate500,
}) {
  return GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: FontWeight.w900,
    color: color,
    letterSpacing: 0.8,
  );
}

TextStyle _sectionTitleStyle({double size = 20}) {
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
}) {
  return GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: color,
    height: 1.45,
  );
}

Color _scoreColor(int score) {
  if (score >= 80) return AppTokens.primary;
  if (score >= 60) return AppTokens.info;
  if (score >= 42) return AppTokens.caution;
  return AppTokens.alert;
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
    case 'sensor_confidence':
      return Icons.sensors_rounded;
    case 'irrigation_decision':
      return Icons.water_drop_rounded;
    case 'crop_stress':
      return Icons.local_florist_rounded;
    case 'soil_health':
      return Icons.terrain_rounded;
    case 'nutrients':
      return Icons.science_rounded;
    case 'ph_suitability':
      return Icons.water_drop_outlined;
    case 'salinity':
      return Icons.grain_rounded;
    case 'spray_timing':
      return Icons.air_rounded;
    case 'pest_disease':
      return Icons.bug_report_outlined;
    case 'stage_readiness':
      return Icons.event_available_rounded;
    default:
      return Icons.eco_rounded;
  }
}
