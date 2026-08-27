import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/monitoring_status.dart';

// ════════════════════════════════════════════════════════════════════════════
//  CropConnect V2 — Scientific Organic Design System
//  Focus: High-Density Data, Fluid Motion, & Modern Scannability
// ════════════════════════════════════════════════════════════════════════════

class AppTokens {
  AppTokens._();

  // ── Colors: The "Forest & Slate" Palette ──────────────────────────────────
  static const primary   = Color(0xFF10B981); // Emerald 500 (Vibrant but Pro)
  static const forest    = Color(0xFF064E3B); // Deep contrast for headlines
  static const canvas    = Color(0xFFFFFFFF);
  static const surface   = Color(0xFFFFFFFF);

  // Neutrals
  static const slate900  = Color(0xFF0F172A);
  static const slate700  = Color(0xFF334155);
  static const slate500  = Color(0xFF64748B);
  static const slate400  = Color(0xFF94A3B8);
  static const slate300  = Color(0xFFE2E8F0);
  static const slate100  = Color(0xFFF8FAFC);
  static const slate50   = Color(0xFFFFFFFF);

  // Semantic
  static const alert     = Color(0xFFEF4444);
  static const caution   = Color(0xFFF59E0B);
  static const info      = Color(0xFF3B82F6);
// ── Typography ──────────────────────────────────────────────────────────
  static TextStyle label() => GoogleFonts.plusJakartaSans(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    color: slate400,
    letterSpacing: 1.2,
  );

  static TextStyle heading() => GoogleFonts.plusJakartaSans(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: slate900,
  );
  /// For large headlines and hero metrics
  static TextStyle display(double size, {Color color = slate900, FontWeight weight = FontWeight.w800}) {
    return GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: -1.0,
    );
  }

  /// For technical data (prevents numbers from jumping)
  static TextStyle mono(double size, {Color color = slate900, FontWeight weight = FontWeight.w700}) {
    return GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }


  // ── Motion Tokens ────────────────────────────────────────────────────────
  static const durationFast = Duration(milliseconds: 200);
  static const durationBase = Duration(milliseconds: 400);
  static const curveFluid   = Curves.easeInOutCubic; // Custom feel
  static const curveSpring  = Curves.easeOutBack;
}

// ─── Component Styling Helpers ──────────────────────────────────────────────

/// Hairline borders for a modern "Glass" look without the blur overhead.
Border sideBorder(BuildContext context) => Border.all(
  color: AppTokens.slate100,
  width: 1.0,
);

/// Professional depth: Use "Spread-less" shadows to keep the UI from looking muddy.
List<BoxShadow> softShadow = [
  BoxShadow(
    color: AppTokens.slate900.withValues(alpha: 0.03),
    blurRadius: 1,
    offset: const Offset(0, 1),
  ),
  BoxShadow(
    color: AppTokens.slate900.withValues(alpha: 0.04),
    blurRadius: 16,
    offset: const Offset(0, 8),
  ),
];

// ─── Typography: Plus Jakarta Sans ──────────────────────────────────────────

ThemeData buildAppTheme() {
  final base = ThemeData.light(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: AppTokens.canvas,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppTokens.primary,
      primary: AppTokens.primary,
      surface: AppTokens.surface,
      error: AppTokens.alert,
    ),

    // Customizing the Text Engine
    textTheme: GoogleFonts.plusJakartaSansTextTheme().copyWith(
      displayMedium: GoogleFonts.plusJakartaSans(
        fontWeight: FontWeight.w800,
        color: AppTokens.forest,
        letterSpacing: -1.2,
      ),
      headlineSmall: GoogleFonts.plusJakartaSans(
        fontWeight: FontWeight.w700,
        color: AppTokens.slate900,
        letterSpacing: -0.5,
      ),
      // Monospace-adjacent look for data figures
      titleLarge: GoogleFonts.plusJakartaSans(
        fontWeight: FontWeight.w800,
        color: AppTokens.slate900,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      bodyMedium: GoogleFonts.plusJakartaSans(
        fontWeight: FontWeight.w700,
        color: AppTokens.slate700,
        height: 1.5,
      ),
      labelSmall: GoogleFonts.plusJakartaSans(
        fontWeight: FontWeight.w700,
        color: AppTokens.slate500,
        letterSpacing: 1.2,
        fontSize: 10,
      ),
    ),

    // Clean Component Themes
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTokens.slate100),
      ),
    ),

    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: AppTokens.canvas,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: AppTokens.forest,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

// ─── Smart Formatting ────────────────────────────────────────────────────────

/// Returns a color-coded status badge feel
class StatusBadge extends StatelessWidget {
  final String status;
  final String label;

  const StatusBadge({super.key, required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─── Semantic Theme Helpers ──────────────────────────────────────────────────
Color surfaceInner(BuildContext context) => AppTokens.slate50;
Color borderColor(BuildContext context) => AppTokens.slate100;
Color textPrimary(BuildContext context) => AppTokens.slate900;
Color textSecondary(BuildContext context) => AppTokens.slate700;
Color textTertiary(BuildContext context) => AppTokens.slate500;
Color surfaceCard(BuildContext context) => AppTokens.surface;
List<BoxShadow> cardShadow(BuildContext context) => softShadow;

// ─── Visual Logic Helpers ────────────────────────────────────────────────────

Color statusColor(String status) {
  final s = status.toLowerCase();
  if (['normal', 'optimal', 'online', 'fresh', 'no_irrigation_needed'].contains(s)) return AppTokens.primary;
  if (['attention', 'warning', 'moderate', 'stale', 'delay_irrigation'].contains(s)) return AppTokens.caution;
  if (['critical', 'offline', 'hot', 'detected', 'start_irrigation'].contains(s)) return AppTokens.alert;
  return AppTokens.slate400;
}

Color irrigationDecisionColor(String decision) => statusColor(decision);

IconData irrigationDecisionIcon(String decision) {
  switch (decision.toLowerCase()) {
    case 'start_irrigation':
      return Icons.water_drop_rounded;
    case 'delay_irrigation':
      return Icons.schedule_rounded;
    case 'hold_decision':
      return Icons.pause_circle_outline_rounded;
    case 'no_irrigation_needed':
      return Icons.verified_rounded;
    default:
      return Icons.water_drop_outlined;
  }
}

IconData statusIcon(String status) {
  final s = status.toLowerCase();
  if (s == 'normal') return Icons.check_circle_outline_rounded;
  if (s == 'attention') return Icons.error_outline_rounded;
  if (s == 'critical') return Icons.emergency_share_rounded;
  return Icons.sensors_rounded;
}

Color severityColor(String severity) => statusColor(severity);
IconData severityIcon(String severity) => statusIcon(severity);

// ─── Data Display ────────────────────────────────────────────────────────────

String formatMetric(double? value, {String suffix = '', int digits = 1}) {
  if (value == null) return '—';
  return '${value.toStringAsFixed(digits)}\u00A0$suffix';
}

String formatNumber(double? value, {int digits = 1}) {
  if (value == null) return '—';
  return value.toStringAsFixed(digits);
}

String formatDateTime(DateTime? value) {
  if (value == null) return '—';
  // Concise "Data Refresh" style format
  final time = "${value.hour}:${value.minute.toString().padLeft(2, '0')}";
  final date = "${value.day}/${value.month}";
  return "$date • $time";
}

// ─── Semantic Descriptions ───────────────────────────────────────────────────

String headlineStatus(String status) {
  switch (status.toLowerCase()) {
    case 'normal':
    case 'optimal':
      return 'Stable Field';
    case 'attention':
    case 'warning':
      return 'Needs Attention';
    case 'critical':
      return 'Critical Action';
    default:
      return 'System Monitoring';
  }
}

String statusDescription(MonitoringStatus? monitoring) {
  if (monitoring == null) return 'Analyzing live field conditions...';
  final count = monitoring.alerts.length;
  if (count == 0) return 'All sensors are within target bands. No active alerts.';
  return 'The monitor has raised $count active alert${count == 1 ? "" : "s"} for this station.';
}

String humanize(String raw) {
  return raw
      .split('_')
      .map((word) => word.isEmpty ? "" : "${word[0].toUpperCase()}${word.substring(1)}")
      .join(' ');
}


// ─── Animations ──────────────────────────────────────────────────────────────

/// Wrap any section in this for a professional "Staggered Entrance"
class SectionReveal extends StatelessWidget {
  final Widget child;
  final Duration delay;

  const SectionReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: AppTokens.durationBase,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
