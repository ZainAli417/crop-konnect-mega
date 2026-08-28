import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/weather_forecast.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Shared kind palette
//
//  Public so the forecast sheet paints its cards from the same source the
//  glyphs are painted from — one weather kind, one colour story.
// ─────────────────────────────────────────────────────────────────────────────

/// The saturated accent for a weather kind — icons, bars, emphasis text.
Color weatherAccent(WeatherKind kind) {
  switch (kind) {
    case WeatherKind.clear:
      return const Color(0xFFF08C00);
    case WeatherKind.partlyCloudy:
      return const Color(0xFF3B82F6);
    case WeatherKind.cloudy:
      return const Color(0xFF64748B);
    case WeatherKind.fog:
      return const Color(0xFF8494A8);
    case WeatherKind.drizzle:
      return const Color(0xFF0EA5E9);
    case WeatherKind.rain:
      return const Color(0xFF2563EB);
    case WeatherKind.showers:
      return const Color(0xFF0E9AA7);
    case WeatherKind.snow:
      return const Color(0xFF60A5FA);
    case WeatherKind.thunderstorm:
      return const Color(0xFF7C3AED);
  }
}

/// A very light wash of the same colour story — safe to put dark text on.
Color weatherWash(WeatherKind kind) {
  switch (kind) {
    case WeatherKind.clear:
      return const Color(0xFFFFF5E1);
    case WeatherKind.partlyCloudy:
      return const Color(0xFFEAF2FE);
    case WeatherKind.cloudy:
      return const Color(0xFFEEF1F5);
    case WeatherKind.fog:
      return const Color(0xFFEFF2F5);
    case WeatherKind.drizzle:
      return const Color(0xFFE7F4FE);
    case WeatherKind.rain:
      return const Color(0xFFE8F0FE);
    case WeatherKind.showers:
      return const Color(0xFFE4F5F8);
    case WeatherKind.snow:
      return const Color(0xFFEDF2FE);
    case WeatherKind.thunderstorm:
      return const Color(0xFFF0EBFC);
  }
}

/// One plain line telling the reader what the sky is actually doing.
/// Written from the field, not from the model.
String weatherHint(WeatherKind kind) {
  switch (kind) {
    case WeatherKind.clear:
      return 'Open sun all day. Water early, cover up at midday.';
    case WeatherKind.partlyCloudy:
      return 'Sun with passing cloud. Good day for field work.';
    case WeatherKind.cloudy:
      return 'Overcast. Cooler leaves, slower drying after irrigation.';
    case WeatherKind.fog:
      return 'Low visibility and damp leaves. Watch for fungal disease.';
    case WeatherKind.drizzle:
      return 'Light patchy rain. Not enough to skip irrigation.';
    case WeatherKind.rain:
      return 'Steady rain likely. Hold irrigation and spraying.';
    case WeatherKind.showers:
      return 'On-and-off showers. Spray only in a dry gap.';
    case WeatherKind.snow:
      return 'Freezing precipitation. Protect young and tender crops.';
    case WeatherKind.thunderstorm:
      return 'Storms with gusts. Secure covers and stay off open ground.';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Glyph
// ─────────────────────────────────────────────────────────────────────────────

/// A continuously animated vector weather mark.
///
/// Everything is painted rather than shipped as an asset, so a glyph stays
/// crisp at any size and the motion (rotating sun rays, drifting cloud,
/// falling drops, a flashing bolt) is driven by one cheap repeating
/// controller instead of a stack of images.
///
/// The mark always carries a semantic label so a screen reader announces
/// "Light rain" rather than an unnamed graphic.
class WeatherGlyph extends StatefulWidget {
  const WeatherGlyph({
    super.key,
    required this.kind,
    this.size = 48,
    this.animate = true,
    this.semanticLabel,
  });

  final WeatherKind kind;
  final double size;

  /// Long lists can freeze their glyphs to keep scrolling cheap.
  final bool animate;

  /// Defaults to the kind's own label.
  final String? semanticLabel;

  @override
  State<WeatherGlyph> createState() => _WeatherGlyphState();
}

class _WeatherGlyphState extends State<WeatherGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void initState() {
    super.initState();
    _apply(animate: widget.animate);
  }

  /// Keeps the ticker in step with the caller's flag and the platform
  /// "reduce motion" setting, which is resolved in [build].
  void _apply({required bool animate}) {
    if (animate) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else if (_ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _apply(animate: widget.animate && !reduceMotion);

    return Semantics(
      label: widget.semanticLabel ?? widget.kind.label,
      image: true,
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              painter: _WeatherPainter(kind: widget.kind, t: _ctrl.value),
            ),
          ),
        ),
      ),
    );
  }
}

/// The glyph plus its name, so a symbol is never left to be guessed at.
///
/// [Axis.vertical] stacks the label under the mark (grids, hero cards);
/// [Axis.horizontal] sets it beside the mark (list rows, chips).
class WeatherGlyphLabel extends StatelessWidget {
  const WeatherGlyphLabel({
    super.key,
    required this.kind,
    this.size = 40,
    this.animate = true,
    this.axis = Axis.vertical,
    this.textStyle,
    this.gap = 6,
  });

  final WeatherKind kind;
  final double size;
  final bool animate;
  final Axis axis;
  final TextStyle? textStyle;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final glyph = WeatherGlyph(kind: kind, size: size, animate: animate);
    final label = Text(
      kind.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textStyle ??
          const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF44505F),
          ),
    );

    if (axis == Axis.horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[glyph, SizedBox(width: gap), Flexible(child: label)],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[glyph, SizedBox(height: gap), label],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Painting
// ─────────────────────────────────────────────────────────────────────────────

/// Palette for the marks. Kept local so a glyph reads the same wherever it is
/// dropped, over light cards or over a coloured header.
class _P {
  static const sunCore = Color(0xFFFFE9A8);
  static const sunEdge = Color(0xFFF97316);
  static const sunRay = Color(0xFFFFB300);
  static const cloudLight = Color(0xFFFFFFFF);
  static const cloudShade = Color(0xFFD7E3F4);
  static const cloudDark = Color(0xFF94A3B8);
  static const cloudStorm = Color(0xFF64748B);
  static const drop = Color(0xFF38BDF8);
  static const dropDeep = Color(0xFF0284C7);
  static const bolt = Color(0xFFFACC15);
  static const flake = Color(0xFFDCEEFF);
  static const fog = Color(0xFFC3CFDD);
  static const shadow = Color(0xFF0F172A);
}

class _WeatherPainter extends CustomPainter {
  _WeatherPainter({required this.kind, required this.t});

  final WeatherKind kind;

  /// Loop progress, 0 to 1.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case WeatherKind.clear:
        _sun(canvas, Offset(size.width * 0.5, size.height * 0.5),
            size.shortestSide * 0.20, halo: true);
        break;

      case WeatherKind.partlyCloudy:
        _sun(canvas, Offset(size.width * 0.66, size.height * 0.32),
            size.shortestSide * 0.165, halo: true);
        _cloud(canvas, _cloudRect(size, dy: 0.10), drift: 0.6);
        break;

      case WeatherKind.cloudy:
        _cloud(canvas, _cloudRect(size, dy: -0.07, scale: 0.80),
            drift: -0.5, shade: _P.cloudShade, top: _P.cloudShade);
        _cloud(canvas, _cloudRect(size, dy: 0.10), drift: 0.7);
        break;

      case WeatherKind.fog:
        _cloud(canvas, _cloudRect(size, dy: -0.06, scale: 0.94), drift: 0.4);
        _fogBars(canvas, size);
        break;

      case WeatherKind.drizzle:
        _cloud(canvas, _cloudRect(size, dy: -0.07), drift: 0.5);
        _drops(canvas, size, count: 3, length: 0.05, speed: 1.6, radius: 1.5);
        break;

      case WeatherKind.rain:
        _cloud(canvas, _cloudRect(size, dy: -0.09), drift: 0.5);
        _drops(canvas, size, count: 4, length: 0.11, speed: 2.4, splash: true);
        break;

      case WeatherKind.showers:
        _sun(canvas, Offset(size.width * 0.72, size.height * 0.22),
            size.shortestSide * 0.125, halo: false);
        _cloud(canvas, _cloudRect(size, dy: -0.08), drift: 0.5);
        _drops(canvas, size,
            count: 5, length: 0.13, speed: 3.0, slant: 0.22, splash: true);
        break;

      case WeatherKind.snow:
        _cloud(canvas, _cloudRect(size, dy: -0.09), drift: 0.4);
        _flakes(canvas, size);
        break;

      case WeatherKind.thunderstorm:
        _cloud(
          canvas,
          _cloudRect(size, dy: -0.11),
          drift: 0.35,
          shade: _P.cloudStorm,
          top: _P.cloudDark,
        );
        _bolt(canvas, size);
        _drops(canvas, size, count: 3, length: 0.08, speed: 2.8, slant: 0.18);
        break;
    }
  }

  // ── Building blocks ───────────────────────────────────────────────────────

  Rect _cloudRect(Size size, {double dy = 0, double scale = 1}) {
    final w = size.width * 0.80 * scale;
    final h = size.height * 0.52 * scale;
    return Rect.fromLTWH(
      (size.width - w) / 2,
      size.height * (0.26 + dy),
      w,
      h,
    );
  }

  void _sun(Canvas canvas, Offset center, double radius,
      {required bool halo}) {
    if (halo) {
      // A breathing glow gives the disc air without adding a second shape.
      final breathe = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
      final haloRadius = radius * (2.5 + 0.18 * breathe);
      canvas.drawCircle(
        center,
        haloRadius,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              _P.sunRay.withValues(alpha: 0.20 + 0.08 * breathe),
              _P.sunRay.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: haloRadius)),
      );
    }

    final rayPaint = Paint()
      ..color = _P.sunRay.withValues(alpha: 0.62)
      ..strokeWidth = math.max(1.4, radius * 0.20)
      ..strokeCap = StrokeCap.round;

    final rotation = t * 2 * math.pi;
    for (var i = 0; i < 8; i++) {
      final angle = rotation + i * math.pi / 4;
      // Rays breathe out of phase with one another.
      final pulse = 0.30 + 0.12 * math.sin(t * 4 * math.pi + i * 0.8);
      final inner = radius * 1.34;
      final outer = inner + radius * pulse;
      canvas.drawLine(
        center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        center + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        rayPaint,
      );
    }

    final disc = Paint()
      ..shader = const RadialGradient(
        colors: <Color>[_P.sunCore, _P.sunEdge],
        stops: <double>[0.35, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, disc);
  }

  Path _cloudPath(Rect r) {
    final w = r.width;
    final h = r.height;
    final base = r.bottom;
    return Path()
      ..addOval(Rect.fromCircle(
          center: Offset(r.left + w * 0.31, base - h * 0.42),
          radius: h * 0.30))
      ..addOval(Rect.fromCircle(
          center: Offset(r.left + w * 0.53, base - h * 0.58),
          radius: h * 0.40))
      ..addOval(Rect.fromCircle(
          center: Offset(r.left + w * 0.74, base - h * 0.38),
          radius: h * 0.26))
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(
            r.left + w * 0.14, base - h * 0.40, r.left + w * 0.86, base),
        Radius.circular(h * 0.22),
      ));
  }

  void _cloud(
    Canvas canvas,
    Rect rect, {
    double drift = 1,
    Color shade = _P.cloudShade,
    Color top = _P.cloudLight,
  }) {
    // A slow lateral sway plus a gentle bob reads as floating without ever
    // leaving the box the glyph was given.
    final dx = math.sin(t * 2 * math.pi) * rect.width * 0.035 * drift;
    final dy = math.cos(t * 2 * math.pi) * rect.height * 0.030 * drift;
    final moved = rect.shift(Offset(dx, dy));
    final path = _cloudPath(moved);

    // A hair of shadow lifts the cloud off the card it sits on.
    canvas.drawPath(
      path.shift(Offset(0, rect.height * 0.055)),
      Paint()
        ..color = _P.shadow.withValues(alpha: 0.07)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, rect.height * 0.10),
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[top, shade],
        ).createShader(moved),
    );
  }

  /// Falling drops that wrap around, each offset in phase so the fall never
  /// looks like a single synchronised row.
  void _drops(
    Canvas canvas,
    Size size, {
    required int count,
    required double length,
    required double speed,
    double slant = 0.12,
    double? radius,
    bool splash = false,
  }) {
    final top = size.height * 0.66;
    final travel = size.height * 0.30;
    final paint = Paint()
      ..strokeWidth = math.max(1.6, size.shortestSide * 0.045)
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < count; i++) {
      final phase = (t * speed + i / count) % 1.0;
      final spread = count == 1 ? 0.5 : i / (count - 1);
      final x = size.width * (0.28 + 0.44 * spread);
      final y = top + travel * phase;

      // Fade in at the top and out at the bottom so drops never pop.
      final fade = math.sin(phase * math.pi).clamp(0.0, 1.0);
      paint.color = (i.isEven ? _P.drop : _P.dropDeep)
          .withValues(alpha: 0.35 + 0.55 * fade);

      if (radius != null) {
        paint.style = PaintingStyle.fill;
        canvas.drawCircle(Offset(x, y), radius, paint);
        continue;
      }
      final dropLength = size.height * length;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + dropLength * slant, y + dropLength),
        paint,
      );

      if (splash && phase > 0.72) {
        // A widening, fading ring where the drop lands.
        final k = (phase - 0.72) / 0.28;
        final ringPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, size.shortestSide * 0.018)
          ..color = _P.drop.withValues(alpha: 0.30 * (1 - k));
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(x, size.height * 0.975),
            width: size.width * (0.06 + 0.10 * k),
            height: size.height * 0.028,
          ),
          ringPaint,
        );
      }
    }
  }

  void _flakes(Canvas canvas, Size size) {
    final top = size.height * 0.64;
    final travel = size.height * 0.32;
    final armLength = size.shortestSide * 0.055;
    final paint = Paint()
      ..strokeWidth = math.max(1.2, size.shortestSide * 0.030)
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 3; i++) {
      final phase = (t * 1.4 + i / 3) % 1.0;
      final sway = math.sin(phase * 2 * math.pi + i) * size.width * 0.04;
      final center = Offset(
        size.width * (0.32 + 0.18 * i) + sway,
        top + travel * phase,
      );
      final fade = math.sin(phase * math.pi).clamp(0.0, 1.0);
      paint.color = _P.flake.withValues(alpha: 0.40 + 0.6 * fade);

      final spin = phase * math.pi;
      for (var arm = 0; arm < 3; arm++) {
        final angle = spin + arm * math.pi / 3;
        final offset =
            Offset(math.cos(angle) * armLength, math.sin(angle) * armLength);
        canvas.drawLine(center - offset, center + offset, paint);
      }
    }
  }

  void _bolt(Canvas canvas, Size size) {
    // Two quick strikes per loop, each a sharp attack with a short decay.
    final strike = (t * 2) % 1.0;
    final flash = strike < 0.16 ? (1 - strike / 0.16) : 0.0;

    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.54, h * 0.58)
      ..lineTo(w * 0.42, h * 0.80)
      ..lineTo(w * 0.51, h * 0.80)
      ..lineTo(w * 0.44, h * 0.98)
      ..lineTo(w * 0.63, h * 0.72)
      ..lineTo(w * 0.53, h * 0.72)
      ..lineTo(w * 0.60, h * 0.58)
      ..close();

    if (flash > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = _P.bolt.withValues(alpha: 0.55 * flash)
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, size.shortestSide * 0.10),
      );
    }
    canvas.drawPath(
      path,
      Paint()..color = _P.bolt.withValues(alpha: 0.72 + 0.28 * flash),
    );
  }

  void _fogBars(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.8, size.shortestSide * 0.055);

    for (var i = 0; i < 3; i++) {
      final phase = math.sin(t * 2 * math.pi + i * 0.9);
      final y = size.height * (0.72 + i * 0.10);
      final inset = size.width * (0.20 + 0.05 * i);
      final shift = phase * size.width * 0.06;
      paint.color = _P.fog.withValues(alpha: 0.78 - i * 0.16);
      canvas.drawLine(
        Offset(inset + shift, y),
        Offset(size.width - inset + shift, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherPainter old) =>
      old.t != t || old.kind != kind;
}