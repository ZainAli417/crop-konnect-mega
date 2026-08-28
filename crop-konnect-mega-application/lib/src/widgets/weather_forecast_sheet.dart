import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/weather_forecast.dart';
import '../viewmodels/station_dashboard_controller.dart';
import 'weather_glyph.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Tokens
//
//  Neutral ground, white cards, hairline outlines, one accent per metric.
//  Deliberately restrained: the glyphs, the numbers and the one-line captions
//  carry the screen, not the chrome.
// ─────────────────────────────────────────────────────────────────────────────

class _C {
  static const bg = Color(0xFFF6F8FB);
  static const surface = Color(0xFFFFFFFF);
  static const container = Color(0xFFF1F4F9);
  static const outline = Color(0xFFE4E9F0);

  static const onSurface = Color(0xFF141A21);
  static const onVariant = Color(0xFF55606E);
  static const onFaint = Color(0xFF93A0B0);

  static const primary = Color(0xFF047857);

  static const rain = Color(0xFF2E7BEA);
  static const wind = Color(0xFF0E9AA7);
  static const uv = Color(0xFFE8890C);
  static const high = Color(0xFFE05252);
  static const low = Color(0xFF4F6DDE);
  static const alert = Color(0xFFB45309);
  static const view = Color(0xFF1F6FEB);
}

TextStyle _t({
  double size = 14,
  FontWeight weight = FontWeight.w600,
  Color color = _C.onSurface,
  double spacing = 0,
  double? height,
}) =>
    GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: height,
    );

const _kFast = Duration(milliseconds: 240);
const _kMed = Duration(milliseconds: 380);

// ─────────────────────────────────────────────────────────────────────────────
//  Formatting
// ─────────────────────────────────────────────────────────────────────────────

const _kWeekdays = <String>[
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];

const _kMonths = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _weekday(DateTime d) => _kWeekdays[d.weekday - 1];

String _monthDay(DateTime d) => '${_kMonths[d.month - 1]} ${d.day}';

String _dayStamp(DateTime d) => '${_weekday(d)}, ${_monthDay(d)}';

String _clock(DateTime? d) {
  if (d == null) return '--';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'am' : 'pm'}';
}

/// "5h 42m" / "58m" / "44s" — compact enough for the button face.
String formatCooldown(Duration d) {
  if (d.inHours >= 1) {
    final minutes = d.inMinutes.remainder(60);
    return '${d.inHours}h ${minutes}m';
  }
  if (d.inMinutes >= 1) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}

String _uvBand(double? uv) {
  if (uv == null) return '';
  if (uv >= 11) return 'extreme';
  if (uv >= 8) return 'very high';
  if (uv >= 6) return 'high';
  if (uv >= 3) return 'moderate';
  return 'low';
}

String _windBand(double? kmh) {
  if (kmh == null) return '';
  if (kmh >= 40) return 'gale — no spraying';
  if (kmh >= 25) return 'strong — drift risk';
  if (kmh >= 12) return 'breezy';
  return 'calm';
}

double? _kmh(double? ms) => ms == null ? null : ms * 3.6;

double _chance(ForecastDay d) =>
    (d.precipitationChance ?? 0).toDouble().clamp(0.0, 100.0);

double _rain(ForecastDay d) => (d.precipitationMm ?? 0).toDouble();

class _Peak {
  const _Peak(this.day, this.value);
  final ForecastDay day;
  final double value;
}

_Peak? _extreme(
  List<ForecastDay> days,
  double? Function(ForecastDay) pick, {
  bool lowest = false,
}) {
  _Peak? best;
  for (final d in days) {
    final v = pick(d);
    if (v == null) continue;
    if (best == null || (lowest ? v < best.value : v > best.value)) {
      best = _Peak(d, v);
    }
  }
  return best;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Predict button
// ─────────────────────────────────────────────────────────────────────────────

/// The call-to-action that sits above the NPK trends.
///
/// Three faces, driven by the controller, and every face states both the
/// action and what it will do:
///   * no outlook held        → "Predict 14-day weather" / what it fetches
///   * request in flight      → "Reading the sky" / progress
///   * outlook held, cooling  → "View forecast" / when it refreshes next
///
/// Once the cooldown runs out the face returns to the predict state on its
/// own, which is what the local one-second ticker is for — the controller does
/// not notify every listener each second just to move a label.
class WeatherPredictButton extends StatefulWidget {
  const WeatherPredictButton({super.key, required this.controller});

  final StationDashboardController controller;

  @override
  State<WeatherPredictButton> createState() => _WeatherPredictButtonState();
}

class _WeatherPredictButtonState extends State<WeatherPredictButton>
    with SingleTickerProviderStateMixin {
  Timer? _ticker;

  /// A slow breath on the leading badge while the button is idle — enough to
  /// read as "live", never enough to nag.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  StationDashboardController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _syncTicker();
    _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  /// Run a one-second ticker only while there is a countdown to show.
  void _syncTicker() {
    final counting = _controller.forecastCooldownRemaining > Duration.zero;
    if (counting && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (_controller.forecastCooldownRemaining == Duration.zero) {
          _ticker?.cancel();
          _ticker = null;
        }
      });
    } else if (!counting) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _syncPulse({required bool loading}) {
    if (loading) {
      if (_pulse.isAnimating) _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  Future<void> _onTap() async {
    final controller = _controller;
    if (controller.isLoadingForecast) return;

    final hasOutlook = controller.weatherForecast != null;
    final cooling = controller.forecastCooldownRemaining > Duration.zero;

    // Cooling down: the held outlook is still perfectly good to read.
    if (hasOutlook && cooling) {
      _open();
      return;
    }

    await controller.fetchWeatherForecast();
    if (!mounted) return;
    _syncTicker();
    setState(() {});

    if (controller.weatherForecast != null) {
      _open();
    } else if (controller.forecastError != null) {
      _showFailure();
    }
  }

  void _open() {
    final forecast = _controller.weatherForecast;
    if (forecast == null) return;
    showWeatherForecastSheet(context, forecast);
  }

  void _showFailure() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _C.onSurface,
        duration: const Duration(seconds: 4),
        content: Row(
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded, size: 17, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No forecast right now. Check the connection and tap again.',
                style: _t(
                    size: 12.5, weight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_controller, _pulse]),
      builder: (context, _) {
        _syncTicker();

        final loading = _controller.isLoadingForecast;
        final remaining = _controller.forecastCooldownRemaining;
        final viewing =
            _controller.weatherForecast != null && remaining > Duration.zero;
        final failed =
            !loading && _controller.weatherForecast == null &&
                _controller.forecastError != null;
        _syncPulse(loading: loading);

        final accent = viewing ? _C.view : _C.primary;
        final title = loading
            ? 'Reading the sky'
            : viewing
                ? 'View forecast'
                : 'Predict 14-day weather';
        final caption = loading
            ? 'Pulling the latest model run for this station'
            : viewing
                ? 'Saved outlook · refreshes in ${formatCooldown(remaining)}'
                : 'Rain, heat, wind and UV for the next two weeks';

        return Container(
          color: _C.surface,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Material(
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  color: accent,
                  child: InkWell(
                    onTap: loading ? null : _onTap,
                    splashColor: Colors.white.withValues(alpha: 0.14),
                    highlightColor: Colors.white.withValues(alpha: 0.06),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(
                        children: <Widget>[
                          _LeadingBadge(
                            loading: loading,
                            viewing: viewing,
                            breath: _pulse.value,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _t(
                                    size: 14.5,
                                    weight: FontWeight.w800,
                                    color: Colors.white,
                                    spacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _t(
                                    size: 11,
                                    weight: FontWeight.w600,
                                    color:
                                        Colors.white.withValues(alpha: 0.82),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (viewing)
                            _CooldownChip(remaining: remaining)
                          else if (!loading)
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.90),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: _kFast,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: failed
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.error_outline_rounded,
                                size: 14, color: _C.alert),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Last attempt failed — tap to try again.',
                                style: _t(
                                    size: 11.5,
                                    weight: FontWeight.w600,
                                    color: _C.alert),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity, height: 0),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LeadingBadge extends StatelessWidget {
  const _LeadingBadge({
    required this.loading,
    required this.viewing,
    required this.breath,
  });

  final bool loading;
  final bool viewing;
  final double breath;

  @override
  Widget build(BuildContext context) {
    final scale = loading ? 1.0 : 1 + 0.05 * breath;

    return Transform.scale(
      scale: scale,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: loading ? 0.16 : 0.18),
          borderRadius: BorderRadius.circular(13),
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(
                viewing
                    ? Icons.calendar_month_rounded
                    : Icons.auto_awesome_rounded,
                size: 19,
                color: Colors.white,
              ),
      ),
    );
  }
}

class _CooldownChip extends StatelessWidget {
  const _CooldownChip({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.schedule_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            formatCooldown(remaining),
            style:
                _t(size: 10.5, weight: FontWeight.w800, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sheet
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showWeatherForecastSheet(
  BuildContext context,
  WeatherForecast forecast,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (_) => _ForecastSheet(forecast: forecast),
  );
}

class _ForecastSheet extends StatelessWidget {
  const _ForecastSheet({required this.forecast});

  final WeatherForecast forecast;

  @override
  Widget build(BuildContext context) {
    final empty = forecast.days.isEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.93,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: ColoredBox(
            color: _C.bg,
            child: Column(
              children: <Widget>[
                _SheetHeader(
                  dayCount: forecast.days.length,
                  onClose: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 30),
                    children: empty
                        ? <Widget>[const _EmptySheet()]
                        : <Widget>[
                            _Reveal(child: _TodayCard(forecast: forecast)),
                            const SizedBox(height: 12),
                            _Reveal(
                              delay: const Duration(milliseconds: 60),
                              child: _AdviceCard(forecast: forecast),
                            ),
                            const SizedBox(height: 12),
                            _Reveal(
                              delay: const Duration(milliseconds: 120),
                              child: _TrendCard(forecast: forecast),
                            ),
                            const SizedBox(height: 12),
                            _Reveal(
                              delay: const Duration(milliseconds: 180),
                              child: _DailyCard(forecast: forecast),
                            ),
                            const SizedBox(height: 12),
                            _Reveal(
                              delay: const Duration(milliseconds: 240),
                              child: _ConditionsCard(forecast: forecast),
                            ),
                            const SizedBox(height: 12),
                            _Reveal(
                              delay: const Duration(milliseconds: 300),
                              child: const _KeyCard(),
                            ),
                          ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.dayCount, required this.onClose});

  final int dayCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.bg,
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 6),
      child: Column(
        children: <Widget>[
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: _C.onFaint.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Weather outlook',
                      style:
                          _t(size: 19, weight: FontWeight.w800, spacing: -0.4),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dayCount == 0
                          ? 'No days available'
                          : 'Next $dayCount days at your station · ${_dayStamp(DateTime.now())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _t(
                          size: 11.5,
                          weight: FontWeight.w600,
                          color: _C.onVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: _C.container,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded,
                      size: 19, color: _C.onVariant),
                  tooltip: 'Close forecast',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptySheet extends StatelessWidget {
  const _EmptySheet();

  @override
  Widget build(BuildContext context) => _Card(
        padding: const EdgeInsets.fromLTRB(18, 26, 18, 26),
        child: Column(
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded, size: 34, color: _C.onFaint),
            const SizedBox(height: 12),
            Text(
              'No forecast days came back',
              style: _t(size: 14.5, weight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Close this sheet and tap Predict again once the station is back online.',
              textAlign: TextAlign.center,
              style: _t(
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: _C.onVariant,
                  height: 1.4),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Card shell + shared bits
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child, this.color, this.padding, this.border});

  final Widget child;
  final Color? color;
  final EdgeInsets? padding;
  final Color? border;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color ?? _C.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: border ?? _C.outline),
        ),
        child: child,
      );
}

/// Every card announces itself with an icon, a title and a plain-language
/// line saying what the reader is looking at.
class _CardHead extends StatelessWidget {
  const _CardHead({
    required this.icon,
    required this.tint,
    required this.title,
    this.caption,
    this.trailing,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: tint),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(size: 13.5, weight: FontWeight.w800, spacing: -0.1),
              ),
              if (caption != null) ...<Widget>[
                const SizedBox(height: 1),
                Text(
                  caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(
                      size: 10.5, weight: FontWeight.w600, color: _C.onFaint),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

/// A small labelled value pill — icon, name, then the number. Used wherever a
/// bare figure would leave the reader guessing at units.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.tint,
    required this.text,
    this.background,
  });

  final IconData icon;
  final Color tint;
  final String text;
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: background ?? _C.container,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 12.5, color: tint),
            const SizedBox(width: 5),
            Text(
              text,
              style:
                  _t(size: 11, weight: FontWeight.w700, color: _C.onSurface),
            ),
          ],
        ),
      );
}

// ── Staggered reveal ─────────────────────────────────────────────────────────

class _Reveal extends StatefulWidget {
  const _Reveal({required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: _kMed);
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    // A short travel reads as settling into place; a long one reads as a
    // slideshow.
    begin: const Offset(0, 0.045),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

/// Counts a figure up on first paint so the headline number arrives instead of
/// simply appearing.
class _CountUp extends StatelessWidget {
  const _CountUp({
    required this.value,
    required this.style,
    this.decimals = 0,
    this.suffix = '',
  });

  final double value;
  final TextStyle style;
  final int decimals;
  final String suffix;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value),
        duration: const Duration(milliseconds: 760),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => Text(
          '${v.toStringAsFixed(decimals)}$suffix',
          style: style,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Today
// ─────────────────────────────────────────────────────────────────────────────

class _TodayCard extends StatefulWidget {
  const _TodayCard({required this.forecast});

  final WeatherForecast forecast;

  @override
  State<_TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<_TodayCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sky = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _sky.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.forecast.today ?? widget.forecast.days.first;
    final kind = today.kind;
    final accent = weatherAccent(kind);
    final wash = weatherWash(kind);
    final maxC = today.tempMaxC;
    final minC = today.tempMinC;
    final windKmh = _kmh(today.windMaxMs);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[wash, Color.lerp(wash, Colors.white, 0.55)!],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.16)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Stack(
          children: <Widget>[
            // Ambient drift so the hero never feels like a static screenshot.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _sky,
                  builder: (context, _) => Align(
                    alignment: Alignment(-0.4 + 1.4 * _sky.value, -0.9),
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: <Color>[
                            accent.withValues(alpha: 0.14),
                            accent.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      _Pill(
                        icon: Icons.today_rounded,
                        tint: accent,
                        text: 'Today',
                        background: Colors.white.withValues(alpha: 0.72),
                      ),
                      const Spacer(),
                      Text(
                        _dayStamp(today.date),
                        style: _t(
                            size: 11.5,
                            weight: FontWeight.w700,
                            color: _C.onVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            // A light weight at display size is what keeps a
                            // big number from shouting.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: maxC == null
                                  ? Text('--',
                                      style: _t(
                                          size: 58, weight: FontWeight.w300))
                                  : _CountUp(
                                      value: maxC,
                                      suffix: '°',
                                      style: _t(
                                        size: 58,
                                        weight: FontWeight.w300,
                                        spacing: -2.6,
                                        height: 1.02,
                                      ),
                                    ),
                            ),
                            Text(
                              'Daytime high',
                              style: _t(
                                  size: 10.5,
                                  weight: FontWeight.w700,
                                  color: _C.onFaint),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              kind.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _t(size: 15.5, weight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: <Widget>[
                                const Icon(Icons.south_rounded,
                                    size: 13, color: _C.low),
                                const SizedBox(width: 3),
                                Text(
                                  minC == null
                                      ? 'Night low --'
                                      : 'Night low ${minC.round()}°',
                                  style: _t(
                                      size: 12.5,
                                      weight: FontWeight.w700,
                                      color: _C.onVariant),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      WeatherGlyph(kind: kind, size: 96),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.tips_and_updates_rounded,
                            size: 15, color: accent),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            weatherHint(kind),
                            style: _t(
                                size: 12,
                                weight: FontWeight.w600,
                                height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      _MiniStat(
                        icon: Icons.water_drop_rounded,
                        tint: _C.rain,
                        label: 'Rain chance',
                        value: '${_chance(today).round()}%',
                        note: 'today',
                      ),
                      const SizedBox(width: 8),
                      _MiniStat(
                        icon: Icons.air_rounded,
                        tint: _C.wind,
                        label: 'Wind gust',
                        value: windKmh == null
                            ? '--'
                            : '${windKmh.round()} km/h',
                        note: _windBand(windKmh),
                      ),
                      const SizedBox(width: 8),
                      _MiniStat(
                        icon: Icons.wb_sunny_rounded,
                        tint: _C.uv,
                        label: 'UV index',
                        value: today.uvIndexMax == null
                            ? '--'
                            : today.uvIndexMax!.toStringAsFixed(1),
                        note: _uvBand(today.uvIndexMax),
                      ),
                    ],
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

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.tint,
    required this.label,
    required this.value,
    required this.note,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 8, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 13, color: tint),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(
                        size: 10, weight: FontWeight.w700, color: _C.onVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: _t(size: 15.5, weight: FontWeight.w800, spacing: -0.4),
              ),
            ),
            if (note.isNotEmpty)
              Text(
                note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    _t(size: 9.5, weight: FontWeight.w600, color: _C.onFaint),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Field advice
// ─────────────────────────────────────────────────────────────────────────────

class _Advice {
  const _Advice({
    required this.icon,
    required this.tint,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String body;
}

List<_Advice> _buildAdvice(WeatherForecast forecast) {
  final out = <_Advice>[];
  final days = forecast.days;
  final wet = forecast.nextWetDay;

  if (wet == null) {
    out.add(_Advice(
      icon: Icons.water_drop_outlined,
      tint: _C.primary,
      title: 'Irrigate on schedule',
      body:
          'No meaningful rain in the next ${days.length} days. Plan watering yourself.',
    ));
  } else {
    out.add(_Advice(
      icon: Icons.umbrella_rounded,
      tint: _C.rain,
      title: wet.isToday
          ? 'Rain today'
          : 'Rain ${_weekday(wet.date)} ${_monthDay(wet.date)}',
      body:
          'About ${_rain(wet).toStringAsFixed(1)} mm expected. Hold irrigation and spraying around it.',
    ));
  }

  final hottest = _extreme(days, (d) => d.tempMaxC);
  if (hottest != null && hottest.value >= 38) {
    out.add(_Advice(
      icon: Icons.local_fire_department_rounded,
      tint: _C.high,
      title: 'Heat stress risk',
      body:
          '${hottest.value.round()}° on ${_weekday(hottest.day.date)}. Water before 9 am and skip midday field work.',
    ));
  }

  final gust = _extreme(days, (d) => _kmh(d.windMaxMs));
  if (gust != null && gust.value >= 25) {
    out.add(_Advice(
      icon: Icons.air_rounded,
      tint: _C.wind,
      title: 'Spray drift risk',
      body:
          'Gusts to ${gust.value.round()} km/h on ${_weekday(gust.day.date)}. Spray on a calmer day.',
    ));
  }

  final uv = _extreme(days, (d) => d.uvIndexMax);
  if (uv != null && uv.value >= 8) {
    out.add(_Advice(
      icon: Icons.wb_sunny_rounded,
      tint: _C.uv,
      title: 'UV ${_uvBand(uv.value)}',
      body:
          'Peaks at ${uv.value.toStringAsFixed(1)} on ${_weekday(uv.day.date)}. Cover up between 10 am and 4 pm.',
    ));
  }

  final coldest = _extreme(days, (d) => d.tempMinC, lowest: true);
  if (coldest != null && coldest.value <= 5) {
    out.add(_Advice(
      icon: Icons.ac_unit_rounded,
      tint: _C.low,
      title: 'Frost watch',
      body:
          '${coldest.value.round()}° overnight on ${_weekday(coldest.day.date)}. Cover tender crops.',
    ));
  }

  return out.take(4).toList();
}

class _AdviceCard extends StatelessWidget {
  const _AdviceCard({required this.forecast});

  final WeatherForecast forecast;

  @override
  Widget build(BuildContext context) {
    final advice = _buildAdvice(forecast);

    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CardHead(
            icon: Icons.agriculture_rounded,
            tint: _C.primary,
            title: 'What to do in the field',
            caption: 'Read from the next ${forecast.days.length} days',
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < advice.length; i++)
            _AdviceRow(
              advice: advice[i],
              showDivider: i != advice.length - 1,
            ),
        ],
      ),
    );
  }
}

class _AdviceRow extends StatelessWidget {
  const _AdviceRow({required this.advice, required this.showDivider});

  final _Advice advice;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: advice.tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(advice.icon, size: 15, color: advice.tint),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      advice.title,
                      style: _t(size: 12.5, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      advice.body,
                      style: _t(
                          size: 11.5,
                          weight: FontWeight.w600,
                          color: _C.onVariant,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: _C.outline.withValues(alpha: 0.8),
            indent: 39,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Trend card
// ─────────────────────────────────────────────────────────────────────────────

enum _Metric { temperature, rain, wind, uv }

extension _MetricMeta on _Metric {
  String get label {
    switch (this) {
      case _Metric.temperature:
        return 'Temp';
      case _Metric.rain:
        return 'Rain';
      case _Metric.wind:
        return 'Wind';
      case _Metric.uv:
        return 'UV';
    }
  }

  String get unit {
    switch (this) {
      case _Metric.temperature:
        return '°C';
      case _Metric.rain:
        return 'mm';
      case _Metric.wind:
        return 'km/h';
      case _Metric.uv:
        return 'index';
    }
  }

  IconData get icon {
    switch (this) {
      case _Metric.temperature:
        return Icons.device_thermostat_rounded;
      case _Metric.rain:
        return Icons.water_drop_rounded;
      case _Metric.wind:
        return Icons.air_rounded;
      case _Metric.uv:
        return Icons.wb_sunny_rounded;
    }
  }

  Color get tint {
    switch (this) {
      case _Metric.temperature:
        return _C.high;
      case _Metric.rain:
        return _C.rain;
      case _Metric.wind:
        return _C.wind;
      case _Metric.uv:
        return _C.uv;
    }
  }
}

String _metricCaption(WeatherForecast forecast, _Metric metric) {
  final days = forecast.days;
  switch (metric) {
    case _Metric.temperature:
      final hot = _extreme(days, (d) => d.tempMaxC);
      final cold = _extreme(days, (d) => d.tempMinC, lowest: true);
      if (hot == null || cold == null) return 'Temperature not reported';
      return 'Hottest ${_weekday(hot.day.date)} ${hot.value.round()}° · '
          'coldest night ${_weekday(cold.day.date)} ${cold.value.round()}°';
    case _Metric.rain:
      final wettest = _extreme(days, (d) => d.precipitationMm);
      if (wettest == null || wettest.value <= 0) {
        return 'Dry across all ${days.length} days';
      }
      return 'Total ${forecast.totalRainMm.toStringAsFixed(1)} mm · heaviest '
          '${_weekday(wettest.day.date)} (${wettest.value.toStringAsFixed(1)} mm)';
    case _Metric.wind:
      final gust = _extreme(days, (d) => _kmh(d.windMaxMs));
      if (gust == null) return 'Wind not reported';
      return 'Strongest gust ${_weekday(gust.day.date)} · '
          '${gust.value.round()} km/h (${_windBand(gust.value)})';
    case _Metric.uv:
      final peak = _extreme(days, (d) => d.uvIndexMax);
      if (peak == null) return 'UV not reported';
      return 'Peak ${peak.value.toStringAsFixed(1)} on '
          '${_weekday(peak.day.date)} · ${_uvBand(peak.value)}';
  }
}

class _TrendCard extends StatefulWidget {
  const _TrendCard({required this.forecast});

  final WeatherForecast forecast;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  _Metric _metric = _Metric.temperature;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CardHead(
            icon: Icons.show_chart_rounded,
            tint: _metric.tint,
            title: 'Trend',
            caption: 'Tap a metric, then touch the chart for a day value',
            trailing: _Pill(
              icon: _metric.icon,
              tint: _metric.tint,
              text: _metric.unit,
            ),
          ),
          const SizedBox(height: 14),
          _Segmented(
            metrics: _Metric.values,
            index: _metric.index,
            onChanged: (i) => setState(() => _metric = _Metric.values[i]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 176,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: KeyedSubtree(
                key: ValueKey<_Metric>(_metric),
                child: _MetricChart(
                  forecast: widget.forecast,
                  metric: _metric,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: _kFast,
            child: Row(
              key: ValueKey<_Metric>(_metric),
              children: <Widget>[
                Icon(Icons.insights_rounded, size: 13, color: _metric.tint),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _metricCaption(widget.forecast, _metric),
                    style: _t(
                        size: 11.5,
                        weight: FontWeight.w600,
                        color: _C.onVariant,
                        height: 1.35),
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

/// A pill-indicator segmented control. The indicator slides rather than jumps,
/// which is what makes switching metrics feel like one surface changing state
/// instead of four separate buttons. Each segment carries its icon *and* its
/// name so the symbol never has to be decoded.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.metrics,
    required this.index,
    required this.onChanged,
  });

  final List<_Metric> metrics;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final segmentWidth = constraints.maxWidth / metrics.length;

        return Container(
          height: 40,
          decoration: BoxDecoration(
            color: _C.container,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: segmentWidth * index,
                top: 3,
                bottom: 3,
                width: segmentWidth,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: _C.surface,
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  for (var i = 0; i < metrics.length; i++)
                    Expanded(
                      // Keyed so a tap target stays unambiguous even when the
                      // same word appears elsewhere on the sheet.
                      key: ValueKey<String>(
                          'trend-segment-${metrics[i].label}'),
                      child: Semantics(
                        button: true,
                        selected: i == index,
                        label:
                            '${metrics[i].label}, shown in ${metrics[i].unit}',
                        excludeSemantics: true,
                        onTap: () => onChanged(i),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onChanged(i),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  metrics[i].icon,
                                  size: 13.5,
                                  color: i == index
                                      ? metrics[i].tint
                                      : _C.onFaint,
                                ),
                                const SizedBox(width: 5),
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 220),
                                  style: _t(
                                    size: 12.5,
                                    weight: i == index
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: i == index
                                        ? _C.onSurface
                                        : _C.onVariant,
                                  ),
                                  child: Text(metrics[i].label),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricChart extends StatelessWidget {
  const _MetricChart({required this.forecast, required this.metric});

  final WeatherForecast forecast;
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final days = forecast.days;
    if (days.isEmpty) return const _EmptyChart();

    // Rain reads as discrete daily totals, so it gets bars; the rest are
    // continuous and get curves.
    if (metric == _Metric.rain) return _RainBars(days: days);
    return _LineTrend(days: days, metric: metric);
  }
}

/// Every third day on a fortnight, every second on a shorter window.
int _axisStep(int length) => length > 9 ? 3 : 2;

FlTitlesData _dayAxis(List<ForecastDay> days, double interval) {
  final step = _axisStep(days.length);

  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 32,
        interval: interval,
        getTitlesWidget: (value, meta) => Text(
          value.round().toString(),
          style: _t(size: 10, weight: FontWeight.w600, color: _C.onFaint),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 26,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final i = value.round();
          if (i < 0 || i >= days.length || i % step != 0) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              days[i].isToday ? 'Now' : _weekday(days[i].date),
              style: _t(
                size: 10,
                weight: FontWeight.w700,
                color: days[i].isToday ? _C.primary : _C.onFaint,
              ),
            ),
          );
        },
      ),
    ),
  );
}

FlGridData _grid(double interval) => FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (_) =>
          const FlLine(color: _C.outline, strokeWidth: 1),
    );

class _LineTrend extends StatelessWidget {
  const _LineTrend({required this.days, required this.metric});

  final List<ForecastDay> days;
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final primary = <FlSpot>[];
    final secondary = <FlSpot>[];

    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      switch (metric) {
        case _Metric.temperature:
          if (d.tempMaxC != null) {
            primary.add(FlSpot(i.toDouble(), d.tempMaxC!));
          }
          if (d.tempMinC != null) {
            secondary.add(FlSpot(i.toDouble(), d.tempMinC!));
          }
          break;
        case _Metric.wind:
          final kmh = _kmh(d.windMaxMs);
          if (kmh != null) primary.add(FlSpot(i.toDouble(), kmh));
          break;
        case _Metric.uv:
          if (d.uvIndexMax != null) {
            primary.add(FlSpot(i.toDouble(), d.uvIndexMax!));
          }
          break;
        case _Metric.rain:
          break;
      }
    }

    if (primary.isEmpty && secondary.isEmpty) return const _EmptyChart();

    final values = <double>[
      ...primary.map((s) => s.y),
      ...secondary.map((s) => s.y),
    ];
    final rawMin = values.reduce(math.min);
    final rawMax = values.reduce(math.max);
    final pad = math.max(1.0, (rawMax - rawMin) * 0.18);
    // Temperature is read as a band, so it keeps a floating baseline; the
    // others are magnitudes and belong on zero.
    final minY = metric == _Metric.temperature ? rawMin - pad : 0.0;
    final maxY = rawMax + pad;
    final interval = math.max(1.0, (maxY - minY) / 4);

    return Column(
      children: <Widget>[
        Expanded(
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (days.length - 1).toDouble(),
              minY: minY,
              maxY: maxY,
              gridData: _grid(interval),
              borderData: FlBorderData(show: false),
              titlesData: _dayAxis(days, interval),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => _C.onSurface,
                  tooltipRoundedRadius: 10,
                  getTooltipItems: (spots) => spots.map((spot) {
                    final i = spot.x.round();
                    final label = i >= 0 && i < days.length
                        ? (days[i].isToday
                            ? 'Today'
                            : _weekday(days[i].date))
                        : '';
                    final band = spot.barIndex == 1 ? 'low' : 'high';
                    final suffix =
                        metric == _Metric.temperature ? ' $band' : '';
                    return LineTooltipItem(
                      '$label$suffix\n${spot.y.round()} ${metric.unit}',
                      _t(
                          size: 11.5,
                          weight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.4),
                    );
                  }).toList(),
                ),
              ),
              betweenBarsData: <BetweenBarsData>[
                if (secondary.isNotEmpty)
                  BetweenBarsData(
                    fromIndex: 0,
                    toIndex: 1,
                    color: _C.high.withValues(alpha: 0.07),
                  ),
              ],
              lineBarsData: <LineChartBarData>[
                _bar(primary, metric.tint, fill: secondary.isEmpty),
                if (secondary.isNotEmpty) _bar(secondary, _C.low),
              ],
            ),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: metric == _Metric.temperature
              ? const <Widget>[
                  _LegendDot(color: _C.high, label: 'Day high'),
                  SizedBox(width: 16),
                  _LegendDot(color: _C.low, label: 'Night low'),
                ]
              : <Widget>[
                  _LegendDot(
                    color: metric.tint,
                    label: metric == _Metric.wind
                        ? 'Strongest gust per day'
                        : 'Highest UV per day',
                  ),
                ],
        ),
      ],
    );
  }

  LineChartBarData _bar(List<FlSpot> spots, Color color, {bool fill = false}) =>
      LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.26,
        barWidth: 2.6,
        color: color,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: fill,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              color.withValues(alpha: 0.20),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      );
}

class _RainBars extends StatelessWidget {
  const _RainBars({required this.days});

  final List<ForecastDay> days;

  @override
  Widget build(BuildContext context) {
    final maxRain =
        days.map(_rain).fold<double>(0, (a, b) => a > b ? a : b);

    if (maxRain <= 0) {
      return const _EmptyChart(
        message: 'No rain expected in this window',
        icon: Icons.wb_sunny_rounded,
      );
    }

    final maxY = maxRain * 1.25;
    final interval = math.max(1.0, maxY / 4);

    return Column(
      children: <Widget>[
        Expanded(
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              gridData: _grid(interval),
              borderData: FlBorderData(show: false),
              titlesData: _dayAxis(days, interval),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => _C.onSurface,
                  tooltipRoundedRadius: 10,
                  getTooltipItem: (group, _, rod, __) {
                    final i = group.x;
                    final label = i >= 0 && i < days.length
                        ? (days[i].isToday ? 'Today' : _weekday(days[i].date))
                        : '';
                    return BarTooltipItem(
                      '$label\n${rod.toY.toStringAsFixed(1)} mm',
                      _t(
                          size: 11.5,
                          weight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.4),
                    );
                  },
                ),
              ),
              barGroups: <BarChartGroupData>[
                for (var i = 0; i < days.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: <BarChartRodData>[
                      BarChartRodData(
                        toY: _rain(days[i]),
                        width: 9,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5)),
                        gradient: const LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: <Color>[Color(0xFF7FB2F5), _C.rain],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            swapAnimationDuration: const Duration(milliseconds: 520),
            swapAnimationCurve: Curves.easeOutCubic,
          ),
        ),
        const SizedBox(height: 8),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _LegendDot(color: _C.rain, label: 'Rain total per day (mm)'),
          ],
        ),
      ],
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart({this.message, this.icon});

  final String? message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon ?? Icons.remove_circle_outline_rounded,
                size: 22, color: _C.onFaint),
            const SizedBox(height: 8),
            Text(
              message ?? 'This metric was not reported for the window',
              textAlign: TextAlign.center,
              style: _t(size: 12, weight: FontWeight.w600, color: _C.onFaint),
            ),
          ],
        ),
      );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: _t(size: 11, weight: FontWeight.w700, color: _C.onVariant),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Daily list
// ─────────────────────────────────────────────────────────────────────────────

class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.forecast});

  final WeatherForecast forecast;

  @override
  Widget build(BuildContext context) {
    final days = forecast.days;

    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CardHead(
            icon: Icons.calendar_month_rounded,
            tint: _C.primary,
            title: 'Day by day',
            caption: 'Tap a day for wind, UV and sun times',
            trailing: _Pill(
              icon: Icons.event_note_rounded,
              tint: _C.onVariant,
              text: '${days.length} days',
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < days.length; i++)
            _DayRow(
              day: days[i],
              warmest: forecast.warmestC,
              coolest: forecast.coolestC,
              // Only the first few glyphs tick; 14 live painters during a
              // flick is not worth the frames.
              animate: i < 4,
              showDivider: i != days.length - 1,
            ),
        ],
      ),
    );
  }
}

class _DayRow extends StatefulWidget {
  const _DayRow({
    required this.day,
    required this.warmest,
    required this.coolest,
    required this.animate,
    required this.showDivider,
  });

  final ForecastDay day;
  final double? warmest;
  final double? coolest;
  final bool animate;
  final bool showDivider;

  @override
  State<_DayRow> createState() => _DayRowState();
}

class _DayRowState extends State<_DayRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final span = (widget.warmest ?? 40) - (widget.coolest ?? 0);
    // Where this day sits inside the fortnight-wide range, as a 0-1 fraction.
    final start = span <= 0 || day.tempMinC == null
        ? 0.0
        : ((day.tempMinC! - (widget.coolest ?? 0)) / span).clamp(0.0, 1.0);
    final end = span <= 0 || day.tempMaxC == null
        ? 1.0
        : ((day.tempMaxC! - (widget.coolest ?? 0)) / span).clamp(0.0, 1.0);

    final chance = _chance(day);
    final mm = _rain(day);

    return Column(
      children: <Widget>[
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
            child: Row(
              children: <Widget>[
                WeatherGlyph(
                    kind: day.kind, size: 34, animate: widget.animate),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        day.isToday
                            ? 'Today · ${_monthDay(day.date)}'
                            : '${_weekday(day.date)} · ${_monthDay(day.date)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _t(
                          size: 12.5,
                          weight:
                              day.isToday ? FontWeight.w800 : FontWeight.w700,
                          color: day.isToday ? _C.primary : _C.onSurface,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              day.kind.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _t(
                                  size: 11,
                                  weight: FontWeight.w600,
                                  color: _C.onVariant),
                            ),
                          ),
                          if (chance > 0) ...<Widget>[
                            const SizedBox(width: 6),
                            Icon(Icons.water_drop_rounded,
                                size: 10,
                                color: chance >= 50 ? _C.rain : _C.onFaint),
                            const SizedBox(width: 2),
                            Text(
                              '${chance.round()}%',
                              style: _t(
                                size: 10.5,
                                weight: FontWeight.w700,
                                color: chance >= 50 ? _C.rain : _C.onFaint,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 24,
                  child: Text(
                    day.tempMinC == null ? '--' : '${day.tempMinC!.round()}°',
                    textAlign: TextAlign.right,
                    style: _t(
                        size: 12, weight: FontWeight.w600, color: _C.onVariant),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(width: 48, child: _RangeBar(start: start, end: end)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 26,
                  child: Text(
                    day.tempMaxC == null ? '--' : '${day.tempMaxC!.round()}°',
                    style: _t(size: 12.5, weight: FontWeight.w800),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: _kFast,
                  child: const Icon(Icons.expand_more_rounded,
                      size: 18, color: _C.onFaint),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: _kFast,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(left: 42, bottom: 10, top: 2),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      _Pill(
                        icon: Icons.water_drop_rounded,
                        tint: _C.rain,
                        text: 'Rain ${mm.toStringAsFixed(1)} mm',
                      ),
                      _Pill(
                        icon: Icons.air_rounded,
                        tint: _C.wind,
                        text: day.windMaxMs == null
                            ? 'Wind --'
                            : 'Wind ${_kmh(day.windMaxMs)!.round()} km/h',
                      ),
                      _Pill(
                        icon: Icons.wb_sunny_rounded,
                        tint: _C.uv,
                        text: day.uvIndexMax == null
                            ? 'UV --'
                            : 'UV ${day.uvIndexMax!.toStringAsFixed(1)} ${_uvBand(day.uvIndexMax)}',
                      ),
                      _Pill(
                        icon: Icons.wb_twilight_rounded,
                        tint: _C.onVariant,
                        text: 'Sunrise ${_clock(day.sunrise)}',
                      ),
                      _Pill(
                        icon: Icons.nightlight_round,
                        tint: _C.low,
                        text: 'Sunset ${_clock(day.sunset)}',
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
        if (widget.showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: _C.outline.withValues(alpha: 0.7),
            indent: 42,
          ),
      ],
    );
  }
}

/// The cool-to-warm segment showing where a day sits in the fortnight range.
/// Grows into place on first paint.
class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.start, required this.end});

  final double start;
  final double end;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final left = width * start;
        final barWidth = math.max(8.0, width * (end - start));

        return SizedBox(
          height: 6,
          child: Stack(
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  color: _C.container,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 480),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Positioned(
                  left: left * value,
                  width: barWidth * value,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[_C.low, Color(0xFFE9A23B), _C.high],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Conditions grid
// ─────────────────────────────────────────────────────────────────────────────

class _ConditionsCard extends StatelessWidget {
  const _ConditionsCard({required this.forecast});

  final WeatherForecast forecast;

  @override
  Widget build(BuildContext context) {
    final today = forecast.today ?? forecast.days.first;
    final windKmh = _kmh(today.windMaxMs);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CardHead(
            icon: Icons.speed_rounded,
            tint: _C.wind,
            title: 'Conditions at a glance',
            caption: 'Today, plus totals for the whole window',
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              _Tile(
                icon: Icons.air_rounded,
                tint: _C.wind,
                label: 'Wind gust today',
                value: windKmh == null ? '--' : '${windKmh.round()}',
                unit: windKmh == null ? 'km/h' : 'km/h · ${_windBand(windKmh)}',
              ),
              const SizedBox(width: 10),
              _Tile(
                icon: Icons.wb_sunny_rounded,
                tint: _C.uv,
                label: 'UV index today',
                value: today.uvIndexMax == null
                    ? '--'
                    : today.uvIndexMax!.toStringAsFixed(1),
                unit: today.uvIndexMax == null
                    ? 'index'
                    : '${_uvBand(today.uvIndexMax)} · 6+ cover up',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              _Tile(
                icon: Icons.water_drop_rounded,
                tint: _C.rain,
                label: 'Rain expected',
                value: forecast.totalRainMm.toStringAsFixed(1),
                unit: 'mm over ${forecast.days.length} days',
              ),
              const SizedBox(width: 10),
              _Tile(
                icon: Icons.device_thermostat_rounded,
                tint: _C.high,
                label: 'Temperature swing',
                value: forecast.warmestC == null || forecast.coolestC == null
                    ? '--'
                    : '${forecast.coolestC!.round()}–${forecast.warmestC!.round()}',
                unit: '°C coldest to hottest',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: _C.container,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.wb_twilight_rounded,
                          size: 16, color: _C.uv),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Sunrise ${_clock(today.sunrise)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _t(size: 12, weight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      const Icon(Icons.nightlight_round,
                          size: 15, color: _C.low),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Sunset ${_clock(today.sunset)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _t(size: 12, weight: FontWeight.w700),
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

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.tint,
    required this.label,
    required this.value,
    required this.unit,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
        decoration: BoxDecoration(
          color: _C.container,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 14, color: tint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(
                        size: 11, weight: FontWeight.w700, color: _C.onVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: _t(size: 22, weight: FontWeight.w700, spacing: -0.8),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              unit,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _t(
                  size: 10.5,
                  weight: FontWeight.w600,
                  color: _C.onFaint,
                  height: 1.25),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Symbol key
//
//  Collapsed by default: it is there for the first-time reader and gets out of
//  the way for everyone else.
// ─────────────────────────────────────────────────────────────────────────────

class _KeyCard extends StatefulWidget {
  const _KeyCard();

  @override
  State<_KeyCard> createState() => _KeyCardState();
}

class _KeyCardState extends State<_KeyCard> {
  bool _open = false;

  static const _entries = <List<String>>[
    <String>['drop', 'Rain chance', 'How likely rain is that day. 50% or more is shown in blue.'],
    <String>['mm', 'Millimetres (mm)', 'How much rain will fall. Roughly 10 mm soaks the top of the soil.'],
    <String>['range', 'Colour bar', 'Where that day sits between the coldest and hottest day of the window.'],
    <String>['wind', 'Wind gust', 'Strongest gust that day, in km/h. Above 25 km/h, spray drifts.'],
    <String>['uv', 'UV index', 'Strength of the sun. 6 or more means cover skin and take shade.'],
    <String>['clock', 'Refresh timer', 'How long until a fresh forecast can be pulled for this station.'],
  ];

  static IconData _icon(String key) {
    switch (key) {
      case 'drop':
        return Icons.water_drop_rounded;
      case 'mm':
        return Icons.opacity_rounded;
      case 'range':
        return Icons.linear_scale_rounded;
      case 'wind':
        return Icons.air_rounded;
      case 'uv':
        return Icons.wb_sunny_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  static Color _tint(String key) {
    switch (key) {
      case 'drop':
      case 'mm':
        return _C.rain;
      case 'range':
        return _C.high;
      case 'wind':
        return _C.wind;
      case 'uv':
        return _C.uv;
      default:
        return _C.onVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _CardHead(
                    icon: Icons.help_outline_rounded,
                    tint: _C.onVariant,
                    title: 'What the symbols mean',
                    caption: _open ? 'Tap to hide' : 'Tap to read the key',
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: _kFast,
                  child: const Icon(Icons.expand_more_rounded,
                      size: 20, color: _C.onFaint),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: _kFast,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _open
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SizedBox(height: 10),
                      for (final e in _entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Icon(_icon(e[0]), size: 15, color: _tint(e[0])),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      e[1],
                                      style: _t(
                                          size: 12, weight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      e[2],
                                      style: _t(
                                          size: 11.5,
                                          weight: FontWeight.w600,
                                          color: _C.onVariant,
                                          height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ],
      ),
    );
  }
}