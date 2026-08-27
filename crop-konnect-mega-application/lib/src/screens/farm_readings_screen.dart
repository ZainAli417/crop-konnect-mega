import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/dashboard_theme.dart';
import '../models/farm.dart';
import '../viewmodels/station_dashboard_controller.dart';
import 'dashboard_tab.dart';

/// A farm's live reading dashboard, opened from a card on the Home tab.
///
/// This is a sub-screen rather than a navigation destination — it is pushed over
/// the shell, so it carries its own back action instead of the nav bar. The
/// "connecting" splash lives here (rather than in the shell) because Home does
/// not depend on the station.
class FarmReadingsScreen extends StatelessWidget {
  const FarmReadingsScreen({
    super.key,
    required this.controller,
    required this.farm,
  });

  final StationDashboardController controller;
  final Farm farm;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final waiting =
                controller.isLoading && controller.latestReading == null;

            if (waiting) {
              return _ConnectingSplash(
                farmName: farm.name,
                onBack: () => Navigator.of(context).maybePop(),
              );
            }

            return DashboardTab(
              controller: controller,
              farm: farm,
              onBack: () => Navigator.of(context).maybePop(),
            );
          },
        ),
      ),
    );
  }
}

/// Shown while the first reading is still in flight. Keeps a back affordance so
/// the user is never stuck here if the station is unreachable.
class _ConnectingSplash extends StatefulWidget {
  const _ConnectingSplash({required this.farmName, required this.onBack});

  final String farmName;
  final VoidCallback onBack;

  @override
  State<_ConnectingSplash> createState() => _ConnectingSplashState();
}

class _ConnectingSplashState extends State<_ConnectingSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Glowing logo mark ──────────────────────────────────────
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF16A34A), Color(0xFF10B981)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppTokens.primary
                            .withValues(alpha: 0.28 + _pulse.value * 0.18),
                        blurRadius: 36,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.sensors_rounded,
                      color: Colors.white, size: 36),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                widget.farmName,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppTokens.slate900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Connecting to station…',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.slate700,
                ),
              ),
              const SizedBox(height: 20),
              // ── Progress bar ───────────────────────────────────────────
              SizedBox(
                width: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const LinearProgressIndicator(
                    backgroundColor: Color(0xFFF1F5F9),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppTokens.primary),
                    minHeight: 3,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Back out even if the station never answers.
        Positioned(
          top: 12,
          left: 12,
          child: IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppTokens.slate700,
            tooltip: 'Back to farms',
          ),
        ),
      ],
    );
  }
}
