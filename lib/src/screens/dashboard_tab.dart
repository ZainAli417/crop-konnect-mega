// ─── Design Tokens ─────────────────────────────────────────────────────────────

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../config/dashboard_theme.dart';
import '../models/dss.dart';
import '../models/monitoring_status.dart';
import '../models/sensor_reading.dart';
import '../models/gps_reading.dart';
import '../viewmodels/station_dashboard_controller.dart';
import '../models/station_trends.dart';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Token System
// ─────────────────────────────────────────────────────────────────────────────

class _T {
  // Surfaces
  static const white = Color(0xFFFFFFFF);
  static const bg = Color(0xFFF8FAFF);

  // Ink scale
  static const ink900 = Color(0xFF0F172A);
  static const ink700 = Color(0xFF334155);
  static const ink500 = Color(0xFF64748B);
  static const ink400 = Color(0xFF94A3B8);
  static const ink200 = Color(0xFFE2E8F0);
  static const ink100 = Color(0xFFF1F5F9);
  static const ink50 = Color(0xFFF8FAFC);

  // Brand green
  static const g600 = Color(0xFF059669);
  static const g500 = Color(0xFF10B981);
  static const g50 = Color(0xFFECFDF5);

  // Accent palette
  static const orange = Color(0xFFF97316);
  static const amber = Color(0xFFF59E0B);
  static const sky = Color(0xFF0EA5E9);
  static const violet = Color(0xFF8B5CF6);
  static const teal = Color(0xFF14B8A6);
  static const red = Color(0xFFEF4444);
  static const red50 = Color(0xFFFEF2F2);

  // Typography
  static TextStyle display({
    double size = 42,
    FontWeight weight = FontWeight.w800,
    Color color = ink900,
    double? height,
    double letterSpacing = -1.0,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextStyle label({
    double size = 11,
    FontWeight weight = FontWeight.w700,
    Color color = ink500,
    double letterSpacing = 1.1,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w600,
    Color color = ink700,
    double? height,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height ?? 1.5,
      );

  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w800,
    Color color = ink900,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: -0.5,
        fontFeatures: [const FontFeature.tabularFigures()],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section Reveal  (staggered fade + slide)
// ─────────────────────────────────────────────────────────────────────────────

class _SectionReveal extends StatefulWidget {
  const _SectionReveal({required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<_SectionReveal> createState() => _SectionRevealState();
}

class _SectionRevealState extends State<_SectionReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Animated Progress Bar
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedBar extends StatefulWidget {
  const _AnimatedBar({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  State<_AnimatedBar> createState() => _AnimatedBarState();
}

class _AnimatedBarState extends State<_AnimatedBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = Tween<double>(begin: 0, end: widget.value)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_AnimatedBar old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _anim = Tween<double>(begin: _anim.value, end: widget.value)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Container(
          height: 5,
          width: double.infinity,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(5),
          ),
          child: FractionallySizedBox(
            widthFactor: _anim.value.clamp(0.0, 1.0),
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Dashboard Tab
// ─────────────────────────────────────────────────────────────────────────────

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key, required this.controller, this.onSettingsTap});
  final StationDashboardController controller;
  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final reading = controller.latestReading;
        final monitoring = controller.monitoringStatus;
        final analysis = controller.dssAnalysis;

        return RefreshIndicator(
          onRefresh: controller.refreshAll,
          color: _T.g600,
          backgroundColor: _T.white,
          displacement: 40,
          child: Container(
            color: const Color(0xFFF6F8FB),
            child: ListView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              scrollCacheExtent: const ScrollCacheExtent.pixels(900),
              padding: EdgeInsets.zero,
              children: [
                // ── Banner ────────────────────────────────────────────
                _SectionReveal(
                  delay: Duration.zero,
                  child: _StatusBanner(
                    reading: reading,
                    monitoring: monitoring,
                    hasConnection: controller.hasConnection,
                    onRefresh: controller.refreshAll,
                    onSettingsTap: onSettingsTap,
                  ),
                ),

                // ── Farmer action summary ────────────────────────────
                _SectionReveal(
                  delay: const Duration(milliseconds: 70),
                  child: _FarmerActionSummary(
                    analysis: analysis,
                    reading: reading,
                  ),
                ),

                // ── Latest reading snapshot ──────────────────────────
                _SectionReveal(
                  delay: const Duration(milliseconds: 110),
                  child: _LatestReadingPanel(reading: reading),
                ),

                // ── Hero strip ────────────────────────────────────────
                _SectionReveal(
                  delay: const Duration(milliseconds: 150),
                  child: RepaintBoundary(
                    child: _HeroMetricStrip(
                      reading: reading,
                      monitoring: monitoring,
                      gps: controller.gpsReading,
                    ),
                  ),
                ),

                // ── Data matrix ───────────────────────────────────────
                _SectionReveal(
                  delay: const Duration(milliseconds: 220),
                  child: RepaintBoundary(
                    child: _ResponsiveDataMatrix(
                      reading: reading,
                      monitoring: monitoring,
                      trends: controller.trends,
                    ),
                  ),
                ),

                // ── Error ─────────────────────────────────────────────
                if (controller.errorMessage != null)
                  _ErrorStrip(message: controller.errorMessage!),

                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Status Banner  ── bold, compact, playful
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.reading,
    required this.monitoring,
    required this.hasConnection,
    required this.onRefresh,
    this.onSettingsTap,
  });

  final SensorReading? reading;
  final MonitoringStatus? monitoring;
  final bool hasConnection;
  final Future<void> Function() onRefresh;
  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final overallStatus = monitoring?.overallStatus ?? 'unknown';
    final accentColor = _statusAccent(overallStatus);
    final statusText = headlineStatus(overallStatus);
    final stationName =
        reading?.stationName ?? monitoring?.stationName ?? 'Field Station';

    return Container(
      width: double.infinity,
      color: _T.white,
      child: Column(
        children: [
          // ── Colour accent bar (top) ──
          Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentColor.withValues(alpha: 0.0),
                  accentColor,
                  accentColor.withValues(alpha: 0.4)
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: LayoutBuilder(builder: (ctx, c) {
              final wide = c.maxWidth >= 600;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: pill + actions
                  Row(
                    children: [
                      _PulsePill(
                        label: hasConnection ? 'LIVE' : 'RECONNECTING',
                        color: hasConnection ? _T.g500 : _T.amber,
                      ),
                      const Spacer(),
                      _TopAction(
                        icon: Icons.refresh_rounded,
                        onTap: onRefresh,
                      ),
                      if (onSettingsTap != null) ...[
                        const SizedBox(width: 4),
                        _TopAction(
                          icon: Icons.tune_rounded,
                          onTap: () => onSettingsTap!(),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Station name + status  (wide = side by side)
                  wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _StationNameBlock(name: stationName),
                            const Spacer(),
                            _StatusBlock(
                              statusText: statusText,
                              accentColor: accentColor,
                              overallStatus: overallStatus,
                              monitoring: monitoring,
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _StationNameBlock(name: stationName),
                            const SizedBox(height: 16),
                            _StatusBlock(
                              statusText: statusText,
                              accentColor: accentColor,
                              overallStatus: overallStatus,
                              monitoring: monitoring,
                            ),
                          ],
                        ),
                ],
              );
            }),
          ),

          // Bottom divider line
          Container(height: 1, color: _T.ink100),
        ],
      ),
    );
  }
}

class _StationNameBlock extends StatelessWidget {
  const _StationNameBlock({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: _T.display(
                size: 26, color: _T.ink900, letterSpacing: -0.8, height: 1.1),
          ),
          const SizedBox(height: 5),
          Text(
            'Smart field monitoring · real-time telemetry',
            style: _T.body(size: 12, color: _T.ink400, weight: FontWeight.w600),
          ),
        ],
      );
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({
    required this.statusText,
    required this.accentColor,
    required this.overallStatus,
    required this.monitoring,
  });
  final String statusText;
  final Color accentColor;
  final String overallStatus;
  final MonitoringStatus? monitoring;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon(overallStatus), color: accentColor, size: 18),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusText,
                  style: _T.display(
                      size: 16, color: accentColor, letterSpacing: -0.3),
                ),
                Text(
                  statusDescription(monitoring),
                  style: _T.label(
                      size: 9.5,
                      color: accentColor.withValues(alpha: 0.7),
                      letterSpacing: 0.4),
                ),
              ],
            ),
          ],
        ),
      );
}

class _TopAction extends StatefulWidget {
  const _TopAction({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_TopAction> createState() => _TopActionState();
}

class _TopActionState extends State<_TopAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _hovered ? _T.ink100 : _T.ink50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _T.ink200),
            ),
            child: Icon(widget.icon,
                size: 17, color: _hovered ? _T.ink700 : _T.ink400),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Farmer Action Summary
// ─────────────────────────────────────────────────────────────────────────────

class _FarmerActionSummary extends StatelessWidget {
  const _FarmerActionSummary({required this.analysis, required this.reading});

  final DssAnalysis? analysis;
  final SensorReading? reading;

  @override
  Widget build(BuildContext context) {
    final recommendation = analysis?.priorityRecommendations.isNotEmpty == true
        ? analysis!.priorityRecommendations.first
        : null;
    final color = recommendation == null
        ? _T.g600
        : _dashboardUrgencyColor(recommendation.urgency);
    final icon = recommendation == null
        ? Icons.check_circle_rounded
        : _dashboardUrgencyIcon(recommendation.urgency);
    final title = recommendation?.title ?? 'No urgent job right now';
    final action = recommendation?.farmerAction ??
        'Keep sensors running and walk the field once today.';
    final check = recommendation?.fieldCheck ??
        'Look for dry patches, wilting leaves, standing water, or damaged plants.';
    final current = analysis;
    final stage = current == null
        ? 'Waiting for crop advisory'
        : '${current.crop.name} · ${current.stage.name}';

    return Container(
      color: _T.white,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TODAY ON FIELD',
                          style: _T.label(size: 9.5, color: color)),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _T.display(
                          size: 20,
                          color: _T.ink900,
                          letterSpacing: -0.4,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(stage,
                          style: _T.body(
                              size: 12,
                              color: _T.ink500,
                              weight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _ActionLine(
              icon: Icons.task_alt_rounded,
              label: 'Do',
              text: action,
              color: color,
            ),
            const SizedBox(height: 8),
            _ActionLine(
              icon: Icons.search_rounded,
              label: 'Check',
              text: check,
              color: _T.ink700,
            ),
            if (reading != null) ...[
              const SizedBox(height: 12),
              Text(
                'Based on last reading: ${_readingAge(reading!.recordedAt)}',
                style: _T.body(
                  size: 11.5,
                  color: _T.ink500,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionLine extends StatelessWidget {
  const _ActionLine({
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
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 9),
        SizedBox(
          width: 46,
          child: Text(label.toUpperCase(),
              style: _T.label(size: 9.5, color: color, letterSpacing: 0.6)),
        ),
        Expanded(
          child: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: _T.body(size: 13, color: _T.ink700, weight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _LatestReadingPanel extends StatelessWidget {
  const _LatestReadingPanel({required this.reading});

  final SensorReading? reading;

  @override
  Widget build(BuildContext context) {
    final r = reading;
    return Container(
      color: _T.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _T.ink50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _T.ink100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sensors_rounded, color: _T.g600, size: 19),
                const SizedBox(width: 8),
                Text('Last Reading',
                    style: _T.display(size: 16, letterSpacing: -0.3)),
                const Spacer(),
                Text(
                  r == null ? 'No data yet' : _readingAge(r.recordedAt),
                  style: _T.label(size: 9.5, color: _T.ink500),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxWidth < 560;
                final chips = <Widget>[
                  _ReadingChip(
                    icon: Icons.water_drop_rounded,
                    label: 'Moisture',
                    value: formatMetric(r?.moist, suffix: '%'),
                    color: _T.g600,
                  ),
                  _ReadingChip(
                    icon: Icons.thermostat_rounded,
                    label: 'Temp',
                    value: formatMetric(r?.temp, suffix: '°C'),
                    color: _T.orange,
                  ),
                  _ReadingChip(
                    icon: Icons.grain_rounded,
                    label: 'Rain',
                    value: formatMetric(r?.rain, suffix: 'mm'),
                    color: _T.violet,
                  ),
                  _ReadingChip(
                    icon: Icons.air_rounded,
                    label: 'Wind',
                    value: formatMetric(r?.ws, suffix: 'm/s'),
                    color: _T.sky,
                  ),
                  _ReadingChip(
                    icon: Icons.wb_sunny_rounded,
                    label: 'Solar',
                    value: formatMetric(r?.solar),
                    color: _T.amber,
                  ),
                ];
                if (compact) {
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
      ),
    );
  }
}

class _ReadingChip extends StatelessWidget {
  const _ReadingChip({
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
      constraints: const BoxConstraints(minWidth: 104),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _T.ink100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _T.label(size: 8.5, color: _T.ink400)),
              const SizedBox(height: 2),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _T.mono(size: 13, color: _T.ink900)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hero Metric Strip
// ─────────────────────────────────────────────────────────────────────────────

class _HeroMetricStrip extends StatelessWidget {
  const _HeroMetricStrip({
    required this.reading,
    required this.monitoring,
    this.gps,
  });

  final SensorReading? reading;
  final MonitoringStatus? monitoring;
  final GpsReading? gps;

  @override
  Widget build(BuildContext context) {
    final lat = gps?.latitude ?? 0.0;
    final lng = gps?.longitude ?? 0.0;
    final hasGps = gps?.latitude != null &&
        gps?.longitude != null &&
        lat.isFinite &&
        lng.isFinite &&
        !(lat == 0.0 && lng == 0.0);

    return Container(
      color: _T.white,
      child: Column(
        children: [
          _MapPanel(
              lat: lat,
              lng: lng,
              hasGps: hasGps,
              height: 320,
              reading: reading),
          Container(height: 1, color: _T.ink100),
        ],
      ),
    );
  }
}

class _MapPanel extends StatefulWidget {
  const _MapPanel({
    required this.lat,
    required this.lng,
    required this.hasGps,
    this.height,
    this.reading,
  });
  final double lat, lng;
  final bool hasGps;
  final double? height;
  final SensorReading? reading;

  @override
  State<_MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends State<_MapPanel> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: SizedBox(
          height: widget.height,
          child: Stack(
            children: [
              if (widget.hasGps)
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(widget.lat, widget.lng),
                    initialZoom: 15,
                    interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.pinchZoom),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                      userAgentPackageName: 'com.ess_sensor_ck.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(widget.lat, widget.lng),
                          width: 80,
                          height: 80,
                          child: Tooltip(
                            message:
                                'Moisture: ${formatMetric(widget.reading?.moist, suffix: '%')}\nTemperature: ${formatMetric(widget.reading?.temp, suffix: '°')}',
                            triggerMode: TooltipTriggerMode.tap,
                            preferBelow: false,
                            child: _StaticMapMarker(color: _T.red),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              else
                Container(
                  color: _T.ink100,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.satellite_alt_rounded,
                            color: _T.ink400, size: 28),
                        const SizedBox(height: 8),
                        Text('Awaiting GPS…',
                            style: _T.label(color: _T.ink400)),
                      ],
                    ),
                  ),
                ),

              // Live HD badge
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.satellite_alt_rounded,
                          color: Colors.white, size: 11),
                      const SizedBox(width: 5),
                      Text('LIVE HD',
                          style: _T.label(
                              size: 8.5,
                              color: Colors.white,
                              letterSpacing: 0.8)),
                    ],
                  ),
                ),
              ),

              // Zoom Controls
              if (widget.hasGps)
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Column(
                    children: [
                      _MapControlButton(
                        icon: Icons.add,
                        onTap: () {
                          _mapController.move(_mapController.camera.center,
                              _mapController.camera.zoom + 1);
                        },
                      ),
                      const SizedBox(height: 5),
                      _MapControlButton(
                        icon: Icons.remove,
                        onTap: () {
                          _mapController.move(_mapController.camera.center,
                              _mapController.camera.zoom - 1);
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Quick Stat Row  ── responsive grid / scroll
// ─────────────────────────────────────────────────────────────────────────────

class _StatData {
  const _StatData(this.icon, this.label, this.value, this.color);
  final IconData icon;
  final String label, value;
  final Color color;
}

class _StatTile extends StatefulWidget {
  const _StatTile({required this.data});
  final _StatData data;

  @override
  State<_StatTile> createState() => _StatTileState();
}

class _StatTileState extends State<_StatTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minWidth: 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _hovered ? d.color.withValues(alpha: 0.08) : _T.ink50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovered ? d.color.withValues(alpha: 0.25) : _T.ink100,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(d.icon, size: 13, color: d.color),
                const SizedBox(width: 5),
                Text(d.label,
                    style: _T.label(
                        size: 9.5,
                        color: d.color.withValues(alpha: 0.8),
                        letterSpacing: 0.4)),
              ],
            ),
            const SizedBox(height: 5),
            Text(d.value,
                style:
                    _T.mono(size: 14, color: _hovered ? d.color : _T.ink900)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Responsive Data Matrix
// ─────────────────────────────────────────────────────────────────────────────

class _ResponsiveDataMatrix extends StatelessWidget {
  const _ResponsiveDataMatrix(
      {required this.reading, required this.monitoring, this.trends});
  final SensorReading? reading;
  final MonitoringStatus? monitoring;
  final StationTrends? trends;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final wide = c.maxWidth > 900;

      if (wide) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 56,
                child: Column(children: [
                  _SectionLabel(
                      title: 'LIVE SENSOR MATRIX',
                      subtitle: 'Root zone & canopy telemetry'),
                  _SensorDataList(reading: reading, monitoring: monitoring),
                ]),
              ),
              Container(width: 1, color: _T.ink100),
              Expanded(
                flex: 44,
                child: Column(children: [
                  _SectionLabel(
                      title: 'SOIL NUTRIENTS', subtitle: 'NPK trend analysis'),
                  _NutrientTrendGraph(reading: reading, trends: trends),
                ]),
              ),
            ],
          ),
        );
      }

      return Column(children: [
        _SectionLabel(
            title: 'LIVE SENSOR MATRIX',
            subtitle: 'Root zone & canopy telemetry'),
        _SensorDataList(reading: reading, monitoring: monitoring),
        Container(height: 8, color: _T.bg),
        _SectionLabel(title: 'SOIL NUTRIENTS', subtitle: 'NPK trend analysis'),
        _NutrientTrendGraph(reading: reading, trends: trends),
      ]);
    });
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Container(
        color: _T.white,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Divider(height: 1, color: _T.ink200)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(title,
                    style: _T.label(
                        size: 10, color: _T.ink400, letterSpacing: 1.5)),
              ),
              Expanded(child: Divider(height: 1, color: _T.ink200)),
            ]),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  style: _T.body(
                      size: 12, color: _T.ink400, weight: FontWeight.w600)),
            ],
            const SizedBox(height: 16),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sensor Data List
// ─────────────────────────────────────────────────────────────────────────────

class _SensorDataList extends StatelessWidget {
  const _SensorDataList({required this.reading, required this.monitoring});
  final SensorReading? reading;
  final MonitoringStatus? monitoring;

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows(reading, monitoring);

    return Container(
      color: _T.white,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: rows.asMap().entries.expand((entry) {
          final i = entry.key;
          final r = entry.value;
          return [
            r,
            if (i < rows.length - 1)
              Divider(height: 1, thickness: 1, color: _T.ink100),
          ];
        }).toList(),
      ),
    );
  }

  List<_SensorRow> _buildRows(SensorReading? r, MonitoringStatus? m) => [
        _SensorRow(
            icon: Icons.water_drop_rounded,
            label: 'Soil Moisture',
            sublabel: 'Root zone saturation',
            value: formatMetric(r?.moist, suffix: '%'),
            barValue: _norm(r?.moist, 0, 100),
            barColor: _T.g600,
            condition: m?.conditions['soil_moisture'],
            conditionColor: _condColor(m?.conditions['soil_moisture'])),
        _SensorRow(
            icon: Icons.thermostat_rounded,
            label: 'Soil Temperature',
            sublabel: 'Ground thermal',
            value: formatMetric(r?.temp, suffix: '°C'),
            barValue: _norm(r?.temp, 0, 60),
            barColor: _T.orange,
            condition: m?.conditions['temperature'],
            conditionColor: _condColor(m?.conditions['temperature'])),
        _SensorRow(
            icon: Icons.air_rounded,
            label: 'Wind Speed',
            sublabel: 'Canopy height',
            value: formatMetric(r?.ws, suffix: ' m/s'),
            barValue: _norm(r?.ws, 0, 30),
            barColor: _T.sky,
            condition: m?.conditions['wind'],
            conditionColor: _condColor(m?.conditions['wind'])),
        _SensorRow(
            icon: Icons.explore_rounded,
            label: 'Wind Direction',
            sublabel: 'Compass heading',
            value: r == null
                ? '--'
                : '${formatNumber(r.wdDeg)}° ${r.wdDir ?? ''}'.trim(),
            barValue: _norm(r?.wdDeg?.toDouble(), 0, 360),
            barColor: _T.ink400,
            condition: null,
            conditionColor: _T.ink400),
        _SensorRow(
            icon: Icons.wb_sunny_rounded,
            label: 'UV / Solar',
            sublabel: 'Photosynthetic radiation',
            value: formatMetric(r?.solar),
            barValue: _norm(r?.solar, 0, 1200),
            barColor: _T.amber,
            condition: m?.conditions['uv'],
            conditionColor: _condColor(m?.conditions['uv'])),
        _SensorRow(
            icon: Icons.grain_rounded,
            label: 'Rainfall',
            sublabel: 'Accumulated precipitation',
            value: formatMetric(r?.rain, suffix: ' mm'),
            barValue: _norm(r?.rain, 0, 50),
            barColor: _T.violet,
            condition: null,
            conditionColor: _T.ink400),
        _SensorRow(
            icon: Icons.bolt_rounded,
            label: 'Electrical Conductivity',
            sublabel: 'Soil salinity index',
            value: formatMetric(r?.ec, suffix: ' µS/cm'),
            barValue: _norm(r?.ec, 0, 2000),
            barColor: _T.ink700,
            condition: null,
            conditionColor: _T.ink400),
        _SensorRow(
            icon: Icons.science_rounded,
            label: 'Soil pH',
            sublabel: 'Acid–alkaline balance',
            value: formatNumber(r?.ph, digits: 2),
            barValue: _norm(r?.ph, 0, 14),
            barColor: _T.teal,
            condition: null,
            conditionColor: _T.ink400),
      ];

  double _norm(double? v, double min, double max) {
    if (v == null) return 0;
    return ((v - min) / (max - min)).clamp(0.0, 1.0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sensor Row
// ─────────────────────────────────────────────────────────────────────────────

class _SensorRow extends StatefulWidget {
  const _SensorRow({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.value,
    required this.barValue,
    required this.barColor,
    required this.condition,
    required this.conditionColor,
  });
  final IconData icon;
  final String label, sublabel, value;
  final double barValue;
  final Color barColor, conditionColor;
  final String? condition;

  @override
  State<_SensorRow> createState() => _SensorRowState();
}

class _SensorRowState extends State<_SensorRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          color: _hovered
              ? widget.barColor.withValues(alpha: 0.03)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: LayoutBuilder(builder: (_, c) {
            final narrow = c.maxWidth < 480;

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _RowIcon(icon: widget.icon, color: widget.barColor),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(widget.label,
                            style: _T.body(size: 13, color: _T.ink700))),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      child: Text(widget.value,
                          key: ValueKey('${widget.label}-${widget.value}'),
                          style: _T.mono(size: 14, color: _T.ink900)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _AnimatedBar(value: widget.barValue, color: widget.barColor),
                  if (widget.condition != null) ...[
                    const SizedBox(height: 5),
                    _ConditionBadge(
                        label: humanize(widget.condition!),
                        color: widget.conditionColor),
                  ],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon + label (fixed width)
                SizedBox(
                  width: 210,
                  child: Row(children: [
                    _RowIcon(icon: widget.icon, color: widget.barColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.label,
                              style: _T.body(size: 12.5, color: _T.ink700)),
                          Text(widget.sublabel,
                              style: _T.body(
                                  size: 10.5,
                                  color: _T.ink400,
                                  weight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ]),
                ),

                // Animated bar
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _AnimatedBar(
                        value: widget.barValue, color: widget.barColor),
                  ),
                ),

                // Value + condition (fixed width)
                SizedBox(
                  width: 115,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        child: Text(widget.value,
                            key: ValueKey('${widget.label}-${widget.value}'),
                            style: _T.mono(size: 15, color: _T.ink900)),
                      ),
                      if (widget.condition != null) ...[
                        const SizedBox(height: 4),
                        _ConditionBadge(
                            label: humanize(widget.condition!),
                            color: widget.conditionColor),
                      ],
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
      );
}

class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 16, color: color),
      );
}

class _ConditionBadge extends StatelessWidget {
  const _ConditionBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label.toUpperCase(),
          style: _T.label(size: 8.5, color: color, letterSpacing: 0.6),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  NPK Trend Graph  (3-wave line chart + legend + advisory)
// ─────────────────────────────────────────────────────────────────────────────

class _NutrientTrendGraph extends StatelessWidget {
  const _NutrientTrendGraph({required this.reading, this.trends});
  final SensorReading? reading;
  final StationTrends? trends;

  static const _nColor = Color(0xFF10B981);
  static const _pColor = Color(0xFFF59E0B);
  static const _kColor = Color(0xFF6366F1);

  @override
  Widget build(BuildContext context) {
    final n = reading?.n?.toDouble() ?? 0;
    final p = reading?.p?.toDouble() ?? 0;
    final k = reading?.k?.toDouble() ?? 0;
    final total = n + p + k;
    final nSeries = trends?.series['n'] ?? [];
    final pSeries = trends?.series['p'] ?? [];
    final kSeries = trends?.series['k'] ?? [];
    final hasData =
        nSeries.isNotEmpty || pSeries.isNotEmpty || kSeries.isNotEmpty;
    final alerts = _buildAdvisories(n, p, k);

    return Container(
      color: _T.white,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(children: [
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NPK Trends',
                    style: _T.display(size: 22, letterSpacing: -0.6)),
                const SizedBox(height: 3),
                Text('Macronutrient concentration over time',
                    style: _T.body(size: 12, color: _T.ink400)),
              ],
            )),
            if (total > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _T.ink50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _T.ink100),
                ),
                child: Text('${total.toStringAsFixed(0)} mg/kg',
                    style: _T.mono(size: 11, color: _T.ink500)),
              ),
          ]),
          const SizedBox(height: 20),

          // ── Legend row ──
          Row(children: [
            _NPKLegendChip(
                symbol: 'N', label: 'Nitrogen', value: n, color: _nColor),
            const SizedBox(width: 8),
            _NPKLegendChip(
                symbol: 'P', label: 'Phosphorus', value: p, color: _pColor),
            const SizedBox(width: 8),
            _NPKLegendChip(
                symbol: 'K', label: 'Potassium', value: k, color: _kColor),
          ]),
          const SizedBox(height: 20),

          // ── Line chart ──
          SizedBox(
            height: 220,
            child: hasData
                ? _buildChart(nSeries, pSeries, kSeries)
                : Center(
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.show_chart_rounded,
                          color: _T.ink200, size: 40),
                      const SizedBox(height: 8),
                      Text('Awaiting trend data…',
                          style: _T.label(color: _T.ink400)),
                    ],
                  )),
          ),

          // ── Advisory alerts ──
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: _T.ink100),
            const SizedBox(height: 14),
            Text('SOIL ADVISORY',
                style:
                    _T.label(size: 9.5, color: _T.ink400, letterSpacing: 1.2)),
            const SizedBox(height: 10),
            ...alerts.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AdvisoryAlert(
                    icon: a.icon,
                    title: a.title,
                    message: a.message,
                    color: a.color,
                    bgColor: a.bgColor,
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildChart(
      List<TrendPoint> nS, List<TrendPoint> pS, List<TrendPoint> kS) {
    final allPoints = [...nS, ...pS, ...kS];
    final allVals = allPoints.map((t) => t.value ?? 0.0).toList();
    if (allVals.isEmpty) allVals.add(0);
    final maxY = (allVals.reduce(math.max) * 1.25).ceilToDouble();
    final minY = (allVals.reduce(math.min) * 0.8).floorToDouble();

    return LineChart(LineChartData(
      minY: minY < 0 ? 0 : minY,
      maxY: maxY < 1 ? 1 : maxY,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: ((maxY - minY) / 4).clamp(1, 999),
        getDrawingHorizontalLine: (v) =>
            FlLine(color: _T.ink100, strokeWidth: 0.8),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
            sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 38,
          getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
              style: _T.label(size: 8, color: _T.ink400, letterSpacing: 0)),
        )),
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          interval: _xInterval(nS.length),
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= nS.length) return const SizedBox.shrink();
            final h = nS[i].timestamp.hour;
            return Text('${h}h',
                style: _T.label(size: 8, color: _T.ink400, letterSpacing: 0));
          },
        )),
      ),
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => _T.ink900.withValues(alpha: 0.92),
          tooltipRoundedRadius: 10,
          tooltipPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          getTooltipItems: (spots) => spots.map((s) {
            final labels = ['N', 'P', 'K'];
            final colors = [_nColor, _pColor, _kColor];
            return LineTooltipItem(
              '${labels[s.barIndex]}  ${s.y.toStringAsFixed(1)} mg/kg',
              GoogleFonts.plusJakartaSans(
                  color: colors[s.barIndex],
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            );
          }).toList(),
        ),
      ),
      lineBarsData: [
        _line(nS, _nColor),
        _line(pS, _pColor),
        _line(kS, _kColor),
      ],
    ));
  }

  double _xInterval(int len) => len <= 6 ? 1 : (len / 6).ceilToDouble();

  LineChartBarData _line(List<TrendPoint> pts, Color color) {
    return LineChartBarData(
      spots: pts
          .asMap()
          .entries
          .map((e) => FlSpot(e.key.toDouble(), e.value.value ?? 0))
          .toList(),
      isCurved: true,
      curveSmoothness: 0.35,
      color: color,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.0)],
        ),
      ),
    );
  }

  List<_Advisory> _buildAdvisories(double n, double p, double k) {
    final list = <_Advisory>[];
    if (n == 0 && p == 0 && k == 0) {
      list.add(_Advisory(
          Icons.info_outline_rounded,
          'No Data',
          'Nutrient sensor readings are unavailable. Check probe connection.',
          _T.ink500,
          _T.ink50));
      return list;
    }
    if (n < 10) {
      list.add(_Advisory(
          Icons.warning_amber_rounded,
          'Low Nitrogen',
          'N is below 10 mg/kg — consider urea or ammonium-based fertilizer.',
          const Color(0xFFEF4444),
          const Color(0xFFFEF2F2)));
    }
    if (n > 40) {
      list.add(_Advisory(
          Icons.eco_rounded,
          'High Nitrogen',
          'N exceeds 40 mg/kg — reduce nitrogen inputs to prevent leaching.',
          _T.amber,
          const Color(0xFFFFFBEB)));
    }
    if (p < 0.5) {
      list.add(_Advisory(
          Icons.warning_amber_rounded,
          'Low Phosphorus',
          'P is below 0.5 mg/kg — apply DAP or SSP fertilizer.',
          const Color(0xFFEF4444),
          const Color(0xFFFEF2F2)));
    }
    if (k < 0.8) {
      list.add(_Advisory(
          Icons.warning_amber_rounded,
          'Low Potassium',
          'K is below 0.8 mg/kg — apply potash (MOP/SOP) to improve crop quality.',
          const Color(0xFFEF4444),
          const Color(0xFFFEF2F2)));
    }
    if (list.isEmpty) {
      list.add(_Advisory(
          Icons.check_circle_outline_rounded,
          'Balanced Nutrients',
          'NPK levels are within optimal range. No corrective action needed.',
          _T.g600,
          _T.g50));
    }
    return list;
  }
}

class _Advisory {
  const _Advisory(
      this.icon, this.title, this.message, this.color, this.bgColor);
  final IconData icon;
  final String title, message;
  final Color color, bgColor;
}

class _NPKLegendChip extends StatelessWidget {
  const _NPKLegendChip({
    required this.symbol,
    required this.label,
    required this.value,
    required this.color,
  });
  final String symbol, label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(symbol,
                  style:
                      _T.body(size: 10, color: color, weight: FontWeight.w900)),
            ),
            const SizedBox(height: 5),
            Text(value > 0 ? value.toStringAsFixed(1) : '—',
                style: _T.mono(size: 15, color: _T.ink900)),
            const SizedBox(height: 1),
            Text(label,
                style:
                    _T.label(size: 7.5, color: _T.ink400, letterSpacing: 0.3)),
          ]),
        ),
      );
}

class _AdvisoryAlert extends StatelessWidget {
  const _AdvisoryAlert({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
    required this.bgColor,
  });
  final IconData icon;
  final String title, message;
  final Color color, bgColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style:
                      _T.body(size: 12, color: color, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(message,
                  style: _T.body(
                      size: 11, color: _T.ink500, weight: FontWeight.w600)),
            ],
          )),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Pulse Pill  (animated live indicator)
// ─────────────────────────────────────────────────────────────────────────────

class _PulsePill extends StatefulWidget {
  const _PulsePill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  State<_PulsePill> createState() => _PulsePillState();
}

class _PulsePillState extends State<_PulsePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.09 + _anim.value * 0.06),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
                color:
                    widget.color.withValues(alpha: 0.25 + _anim.value * 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color:
                      widget.color.withValues(alpha: 0.7 + _anim.value * 0.3),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(widget.label,
                  style: _T.label(
                      size: 10, color: widget.color, letterSpacing: 0.9)),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Static Map Marker
// ─────────────────────────────────────────────────────────────────────────────

class _StaticMapMarker extends StatelessWidget {
  const _StaticMapMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.25),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Error Strip
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _T.red50,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: _T.red, width: 3)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: _T.red, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: _T.body(
                      size: 12, color: _T.red, weight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────────────────────

Color _statusAccent(String status) {
  switch (status.toLowerCase()) {
    case 'optimal':
    case 'good':
      return _T.g500;
    case 'warning':
    case 'caution':
      return _T.amber;
    case 'critical':
    case 'alert':
      return _T.red;
    default:
      return _T.ink400;
  }
}

Color _condColor(String? condition) {
  if (condition == null) return _T.ink400;
  switch (condition.toLowerCase()) {
    case 'optimal':
    case 'good':
      return _T.g600;
    case 'warning':
    case 'caution':
      return _T.amber;
    case 'critical':
    case 'alert':
      return _T.red;
    default:
      return _T.ink500;
  }
}

Color _dashboardUrgencyColor(DssUrgency urgency) {
  switch (urgency) {
    case DssUrgency.critical:
    case DssUrgency.high:
      return _T.red;
    case DssUrgency.moderate:
      return _T.amber;
    case DssUrgency.low:
      return _T.sky;
    case DssUrgency.info:
      return _T.ink500;
  }
}

IconData _dashboardUrgencyIcon(DssUrgency urgency) {
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

String _readingAge(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
}
