import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/dashboard_theme.dart';

// ─── Staggered section reveal ─────────────────────────────────────────────────

// SectionReveal is now provided by dashboard_theme.dart


// ─── Loading view ─────────────────────────────────────────────────────────────

class LoadingView extends StatefulWidget {
  const LoadingView({super.key});

  @override
  State<LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<LoadingView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => Opacity(
          opacity: _pulse.value,
          child: child,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTokens.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: AppTokens.primary.withValues(alpha: 0.2)),
              ),
              child: const Icon(Icons.sensors_rounded,
                  color: AppTokens.primary, size: 36),
            ),
            const SizedBox(height: 20),
            Text(
              'Connecting to station…',
              style: GoogleFonts.plusJakartaSans(
                    color: AppTokens.slate700,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pulsing status dot ───────────────────────────────────────────────────────

class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, required this.color});
  final Color color;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.55 * _controller.value),
              blurRadius: 10 * _controller.value,
              spreadRadius: 2 * _controller.value,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Title ────────────────────────────────────────────────────────────

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 24,
            color: AppTokens.slate900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: GoogleFonts.plusJakartaSans(
                color: AppTokens.slate500,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                height: 1.5,
              ),
        ),
      ],
    );
  }
}

// ─── Content Card Container ──────────────────────────────────────────────────

class ContentCard extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor; // Add this line

  const ContentCard({
    super.key,
    required this.child,
    this.backgroundColor, // Add this line
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTokens.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTokens.slate100),
        boxShadow: softShadow,
      ),
      child: child,
    );
  }
}
