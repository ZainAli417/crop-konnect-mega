import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/dashboard_theme.dart';
import '../models/monitoring_status.dart';
import '../viewmodels/station_dashboard_controller.dart';
import '../widgets/shared_widgets.dart';

// ─── Health Tab ───────────────────────────────────────────────────────────────

class HealthTab extends StatelessWidget {
  const HealthTab({
    super.key,
    required this.controller,
  });

  final StationDashboardController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final monitoring = controller.monitoringStatus;

        return RefreshIndicator(
          onRefresh: controller.refreshMonitoringStatus,
          displacement: 20,
          color: AppTokens.primary,
          backgroundColor: Colors.white,
          strokeWidth: 2.5,
          child: ListView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),

              SectionReveal(
                delay: Duration.zero,
                child: _ConditionSection(monitoring: monitoring),
              ),
              const SizedBox(height: 32),

              SectionReveal(
                delay: const Duration(milliseconds: 100),
                child: _SensorHealthSection(monitoring: monitoring),
              ),
              const SizedBox(height: 32),

              SectionReveal(
                delay: const Duration(milliseconds: 200),
                child: _AlertsSection(monitoring: monitoring),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'System Integrity',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w900,
            color: AppTokens.slate900,
            letterSpacing: -1,
            fontSize: 28,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppTokens.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

// ─── Conditions Section ───────────────────────────────────────────────────────

class _ConditionSection extends StatelessWidget {
  const _ConditionSection({required this.monitoring});
  final MonitoringStatus? monitoring;

  @override
  Widget build(BuildContext context) {
    final entries = <MapEntry<String, String>>[
      MapEntry('Moisture', monitoring?.conditions['soil_moisture'] ?? 'unknown'),
      MapEntry('Temp', monitoring?.conditions['temperature'] ?? 'unknown'),
      MapEntry('Rain', monitoring?.conditions['rain'] ?? 'unknown'),
      MapEntry('Wind', monitoring?.conditions['wind'] ?? 'unknown'),
      MapEntry('UV', monitoring?.conditions['uv'] ?? 'unknown'),
      MapEntry('EC', monitoring?.conditions['ec'] ?? 'unknown'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: entries
              .map((e) => _ConditionBadge(label: e.key, value: e.value))
              .toList(),
        ),
      ],
    );
  }
}

// ─── Sensor Health Section ────────────────────────────────────────────────────

class _SensorHealthSection extends StatelessWidget {
  const _SensorHealthSection({required this.monitoring});
  final MonitoringStatus? monitoring;

  @override
  Widget build(BuildContext context) {
    final health = monitoring?.sensorHealth ?? <String, SensorHealth>{};
    final items = [
      _SensorHealthCard(label: 'Wind Speed', health: health['wind'], icon: Icons.air),
      _SensorHealthCard(label: 'Soil Probe', health: health['soil'], icon: Icons.psychology_rounded),
      _SensorHealthCard(label: 'Rain Gauge', health: health['rain'], icon: Icons.water_drop_outlined),
      _SensorHealthCard(label: 'UV Index', health: health['uv'], icon: Icons.wb_sunny_outlined),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'Component Health',
          subtitle: 'Active monitoring of hardware signal freshness',
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900 ? 4 : 2;
            final gap = 16.0;
            final itemWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in items)
                  SizedBox(
                    width: itemWidth,
                    child: RepaintBoundary(child: item),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Alerts Section ───────────────────────────────────────────────────────────

class _AlertsSection extends StatelessWidget {
  const _AlertsSection({required this.monitoring});
  final MonitoringStatus? monitoring;

  @override
  Widget build(BuildContext context) {
    final alerts = monitoring?.alerts ?? const <MonitoringAlert>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Active Intelligence',
          subtitle: alerts.isEmpty
              ? 'All systems operating within normal parameters.'
              : 'Actionable insights derived from field data.',
        ),
        const SizedBox(height: 16),
        if (alerts.isEmpty)
          _buildEmptyState(context)
        else
          ...alerts.map((alert) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _AlertTile(alert: alert),
          )),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: Color(0xFF10B981), size: 40),
          const SizedBox(height: 12),
          Text(
            'System Stable',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1E293B),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'No anomalies detected in the last 24 hours.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Refined Sub-widgets ──────────────────────────────────────────────────────

class _ConditionBadge extends StatelessWidget {
  const _ConditionBadge({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(value);
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 500),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, opacity, child) {
        return Opacity(
          opacity: opacity,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  humanize(value),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color.withValues(alpha: 0.9),
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

class _SensorHealthCard extends StatelessWidget {
  const _SensorHealthCard({
    required this.label,
    required this.health,
    required this.icon,
  });
  final String label;
  final SensorHealth? health;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final status = health?.status ?? 'unknown';
    final color = statusColor(status);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E293B).withValues(alpha: 0.03),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 20, color: const Color(0xFF94A3B8)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  humanize(status).toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                      color: color, fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            health?.freshness ?? 'N/A',
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF1E293B),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});
  final MonitoringAlert alert;

  @override
  Widget build(BuildContext context) {
    final color = severityColor(alert.severity);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              right: null,
              child: ColoredBox(color: color, child: const SizedBox(width: 6)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(severityIcon(alert.severity), color: color, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          alert.title,
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1E293B),
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        formatDateTime(alert.timestamp),
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF94A3B8),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    alert.message,
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF475569),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
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
