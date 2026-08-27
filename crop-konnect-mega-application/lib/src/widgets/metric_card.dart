import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/dashboard_theme.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.colors,
    this.subtitle,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final List<Color> colors;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final accentColor = colors.last;

    return Container(
      decoration: BoxDecoration(
        color: surfaceCard(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor(context)),
        boxShadow: cardShadow(context),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: textPrimary(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: textSecondary(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: GoogleFonts.plusJakartaSans(
                      color: textPrimary(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                    ),
                  ),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: GoogleFonts.plusJakartaSans(
                        color: textTertiary(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
