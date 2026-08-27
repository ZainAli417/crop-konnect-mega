import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../viewmodels/station_dashboard_controller.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────

class _Tok {
  static const surface = Colors.white;
  static const slate900 = Color(0xFF0F172A);
  static const slate700 = Color(0xFF334155);
  static const slate500 = Color(0xFF64748B);
  static const slate400 = Color(0xFF94A3B8);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate100 = Color(0xFFF1F5F9);

  static const blue = Color(0xFF3B82F6);
  static const amber = Color(0xFFF59E0B);
  static const emerald = Color(0xFF10B981);
  static const violet = Color(0xFF8B5CF6);
  static const rose = Color(0xFFF43F5E);
}

// ─── Trend Config ─────────────────────────────────────────────────────────────

class TrendConfig {
  final String key;
  final String title;
  final String unit;
  final Color color;
  final IconData icon;
  final double minSeed;
  final double maxSeed;

  const TrendConfig({
    required this.key,
    required this.title,
    required this.unit,
    required this.color,
    required this.icon,
    required this.minSeed,
    required this.maxSeed,
  });
}

const _configs = [
  TrendConfig(
    key: 'moist',
    title: 'Soil Moisture',
    unit: '%',
    color: _Tok.blue,
    icon: Icons.water_drop_outlined,
    minSeed: 30,
    maxSeed: 80,
  ),
  TrendConfig(
    key: 'temp',
    title: 'Temperature',
    unit: '°C',
    color: _Tok.amber,
    icon: Icons.thermostat_outlined,
    minSeed: 18,
    maxSeed: 38,
  ),
  TrendConfig(
    key: 'ws',
    title: 'Wind Speed',
    unit: ' m/s',
    color: _Tok.emerald,
    icon: Icons.air_outlined,
    minSeed: 0,
    maxSeed: 15,
  ),
  TrendConfig(
    key: 'uv',
    title: 'UV Index',
    unit: '',
    color: _Tok.violet,
    icon: Icons.wb_sunny_outlined,
    minSeed: 0,
    maxSeed: 11,
  ),
];


// ─── Trends Tab ───────────────────────────────────────────────────────────────

class TrendsTab extends StatelessWidget {
  const TrendsTab({super.key, required this.controller});
  final StationDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
              children: [
                _Header(),
                const SizedBox(height: 28),
                _TrendGrid(controller: controller),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(
                color: _Tok.blue,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analytics & Trends',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: _Tok.slate900,
                    letterSpacing: -0.8,
                    height: 1.1,
                  ),
                ),
                Text(
                  '24-hour live field indicators',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _Tok.slate500,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const Spacer(),
            _LiveBadge(),
          ],
        ),
      ],
    );
  }
}

class _LiveBadge extends StatefulWidget {
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _Tok.emerald.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _Tok.emerald.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _Tok.emerald.withValues(
                    alpha: 0.5 + 0.5 * _pulse.value,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'LIVE',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _Tok.emerald,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrendGrid extends StatelessWidget {
  final StationDashboardController controller;
  const _TrendGrid({required this.controller});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 800 ? 2 : 1;
        if (cols == 1) {
          return Column(
            children: [
              for (int i = 0; i < _configs.length; i++) ...[
                LiveTrendCard(config: _configs[i], controller: controller),
                if (i < _configs.length - 1) const SizedBox(height: 16),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (int row = 0; row < (_configs.length / 2).ceil(); row++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int col = 0; col < 2; col++)
                    if (row * 2 + col < _configs.length) ...[
                      Expanded(
                        child: LiveTrendCard(
                          config: _configs[row * 2 + col],
                          controller: controller,
                        ),
                      ),
                      if (col == 0) const SizedBox(width: 16),
                    ] else if (col == 1)
                      const Expanded(child: SizedBox()),
                ],
              ),
              if (row < (_configs.length / 2).ceil() - 1)
                const SizedBox(height: 16),
            ],
          ],
        );
      },
    );
  }
}

class LiveTrendCard extends StatefulWidget {
  final TrendConfig config;
  final StationDashboardController controller;
  const LiveTrendCard({super.key, required this.config, required this.controller});

  @override
  State<LiveTrendCard> createState() => _LiveTrendCardState();
}

class _LiveTrendCardState extends State<LiveTrendCard>
    with TickerProviderStateMixin {
  static const _maxPoints = 40;

  final List<double> _values = [];

  late AnimationController _valueAnimCtrl;
  late Animation<double> _valueAnim;

  double _prevLatest = 0;
  double _nextLatest = 0;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _valueAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _valueAnim = Tween<double>(begin: 0, end: 0).animate(_valueAnimCtrl);
    _syncWithController();
  }

  @override
  void didUpdateWidget(LiveTrendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWithController();
  }

  void _syncWithController() {
    final trends = widget.controller.trends?.series[widget.config.key];
    if (trends != null && trends.isNotEmpty) {
      final newPoints = trends.map((p) => p.value ?? 0.0).toList();
      if (newPoints.length != _values.length || (newPoints.isNotEmpty && newPoints.last != _values.last)) {
        setState(() {
          _values.clear();
          _values.addAll(newPoints);
          if (_values.length > _maxPoints) {
            _values.removeRange(0, _values.length - _maxPoints);
          }
          _updateLatest(_values.last);
        });
      }
    }

    // Check for live updates from latestReading
    final latest = widget.controller.latestReading;
    if (latest != null) {
      double? val;
      switch (widget.config.key) {
        case 'moist': val = latest.moist; break;
        case 'temp':  val = latest.temp;  break;
        case 'ws':    val = latest.ws;    break;
        case 'uv':    val = latest.solar; break; // Mapping UV to Solar if UV not direct
      }
      if (val != null && val != _nextLatest) {
        _pushNewValue(val);
      }
    }
  }

  void _pushNewValue(double val) {
    if (!mounted) return;
    setState(() {
      _values.add(val);
      if (_values.length > _maxPoints) _values.removeAt(0);
      _updateLatest(val);
    });
  }

  void _updateLatest(double val) {
    _prevLatest = _nextLatest;
    _nextLatest = val;
    _valueAnim = Tween<double>(begin: _prevLatest, end: _nextLatest).animate(
      CurvedAnimation(parent: _valueAnimCtrl, curve: Curves.easeInOutCubic),
    );
    _valueAnimCtrl.reset();
    _valueAnimCtrl.forward();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _valueAnimCtrl.dispose();
    super.dispose();
  }

  List<FlSpot> get _spots => _values.asMap().entries.map((e) {
    return FlSpot(e.key.toDouble(), e.value);
  }).toList();

  double get _minVal {
    if (_values.isEmpty) return 0.0;
    final min = _values.reduce((a, b) => a < b ? a : b);
    return min.isFinite ? min : 0.0;
  }
  double get _maxVal {
    if (_values.isEmpty) return 1.0;
    final max = _values.reduce((a, b) => a > b ? a : b);
    return max.isFinite ? max : 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    final spots = _spots;
    final range = (_maxVal - _minVal).abs() < 0.001 ? 1.0 : _maxVal - _minVal;
    final pad = range * 0.2;

    return Container(
      decoration: BoxDecoration(
        color: _Tok.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cfg.color.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: _Tok.slate900.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon badge
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cfg.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(cfg.icon, color: cfg.color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cfg.title.toUpperCase(),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: _Tok.slate400,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedBuilder(
                        animation: _valueAnim,
                        builder: (_, __) {
                          return Text(
                            '${_valueAnim.value.toStringAsFixed(1)}${cfg.unit}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: _Tok.slate900,
                              letterSpacing: -1,
                              height: 1.0,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                // Delta chip
                _DeltaChip(values: _values, color: cfg.color),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Chart — no clipping, overflow visible
          SizedBox(
            height: 130,
            child: spots.length < 2



            
                ? Center(
              child: Text(
                'Awaiting data…',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _Tok.slate300,
                ),
              ),
            )
                : Padding(
              padding: const EdgeInsets.only(right: 8),
              child: LineChart(
                LineChartData(
                  clipData: const FlClipData.none(), // ← no clipping
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: range / 3,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: _Tok.slate100,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (val, meta) {
                          if (val == meta.min || val == meta.max) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text(
                              val.toStringAsFixed(0),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                color: _Tok.slate300,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: _minVal - pad,
                  maxY: _maxVal + pad,
                  lineTouchData: LineTouchData(
                    handleBuiltInTouches: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => _Tok.slate900,
                      tooltipRoundedRadius: 10,
                      tooltipPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      getTooltipItems: (spots) => spots
                          .map((s) => LineTooltipItem(
                        '${s.y.toStringAsFixed(1)}${cfg.unit}',
                        GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ))
                          .toList(),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.35,
                      color: cfg.color,
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      preventCurveOverShooting: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, pct, bar, idx) {
                          // Show a visible dot only for the last point
                          if (idx == spots.length - 1) {
                            return FlDotCirclePainter(
                              radius: 4,
                              color: Colors.white,
                              strokeWidth: 2.5,
                              strokeColor: cfg.color,
                            );
                          }
                          return FlDotCirclePainter(
                            radius: 0,
                            color: Colors.transparent,
                            strokeWidth: 0,
                            strokeColor: Colors.transparent,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            cfg.color.withValues(alpha: 0.18),
                            cfg.color.withValues(alpha: 0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOutCubic,
              ),
            ),
          ),

          // ── Footer Stats
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Row(
              children: [
                _FooterStat(
                  label: 'LOW',
                  value: '${_minVal.toStringAsFixed(1)}${cfg.unit}',
                  color: cfg.color.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 20),
                _FooterStat(
                  label: 'HIGH',
                  value: '${_maxVal.toStringAsFixed(1)}${cfg.unit}',
                  color: cfg.color,
                ),
                const Spacer(),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _Tok.slate100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '24H WINDOW',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: _Tok.slate400,
                      letterSpacing: 1,
                    ),
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

// ─── Delta Chip ───────────────────────────────────────────────────────────────

class _DeltaChip extends StatelessWidget {
  final List<double> values;
  final Color color;
  const _DeltaChip({required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox.shrink();
    final delta = values.last - values[values.length - 2];
    final isUp = delta >= 0;
    final bgColor = isUp
        ? _Tok.emerald.withValues(alpha: 0.1)
        : _Tok.rose.withValues(alpha: 0.1);
    final fgColor = isUp ? _Tok.emerald : _Tok.rose;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 13,
            color: fgColor,
          ),
          const SizedBox(width: 3),
          Text(
            '${isUp ? '+' : ''}${delta.toStringAsFixed(1)}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Footer Stat ──────────────────────────────────────────────────────────────

class _FooterStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _FooterStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: _Tok.slate400,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _Tok.slate700,
          ),
        ),
      ],
    );
  }
}
