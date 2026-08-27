import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/dashboard_theme.dart';
import '../models/farm.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Home — the first navigation destination.
//  Lists the farms this account can open as cards. Tapping a card pushes that
//  farm's live reading dashboard as a sub-screen, so the nav bar stays put.
//
//  Farms come from the Supabase `farms` table via FarmCatalog, which serves a
//  built-in farm until the table loads (and if it fails), so this screen is
//  never empty.
// ════════════════════════════════════════════════════════════════════════════

class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.onOpenFarm,
    this.onReloadFarms,
  });

  /// Opens a farm's reading dashboard.
  final ValueChanged<Farm> onOpenFarm;

  /// Refetches the farm list. Null hides pull-to-refresh.
  final Future<void> Function()? onReloadFarms;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Future<void> _refresh() async {
    final reload = widget.onReloadFarms;
    if (reload != null) await reload();
  }

  @override
  Widget build(BuildContext context) {
    // The shell caches its tabs, so a setState there will not reach this
    // widget. Listening to FarmCatalog.revision is what makes a freshly loaded
    // farm list appear.
    return ValueListenableBuilder<int>(
      valueListenable: FarmCatalog.revision,
      builder: (context, _, __) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final farms = FarmCatalog.farms;

    final list = ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 36),
      children: [
        const _HomeHeader(),
        const SizedBox(height: 20),

        // Only worth mentioning once a load actually failed — otherwise the
        // built-in farm is indistinguishable from a loaded one.
        if (FarmCatalog.hasLoaded && FarmCatalog.lastError != null) ...[
          const _OfflineFarmsNotice(),
          const SizedBox(height: 14),
        ],

        Row(
          children: [
            Text('YOUR FARMS', style: _labelStyle(size: 10)),
            const Spacer(),
            if (!FarmCatalog.hasLoaded)
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                '${farms.length} ${farms.length == 1 ? 'farm' : 'farms'}',
                style: _labelStyle(size: 10, color: AppTokens.primary),
              ),
          ],
        ),
        const SizedBox(height: 12),

        for (var i = 0; i < farms.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == farms.length - 1 ? 0 : 14),
            child: SectionReveal(
              child: _FarmCard(
                farm: farms[i],
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onOpenFarm(farms[i]);
                },
              ),
            ),
          ),
      ],
    );

    return Container(
      color: const Color(0xFFF6F8FB),
      child: widget.onReloadFarms == null
          ? list
          : RefreshIndicator(
              onRefresh: _refresh,
              color: AppTokens.primary,
              backgroundColor: Colors.white,
              child: list,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────── Header ──

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF16A34A), Color(0xFF10B981)],
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: AppTokens.primary.withValues(alpha: 0.32),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: const Icon(Icons.eco_rounded, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Crop Konnect',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppTokens.slate900,
                  letterSpacing: -0.9,
                ),
              ),
              Text(
                'Pick a farm to open its dashboard',
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
      ],
    );
  }
}

class _OfflineFarmsNotice extends StatelessWidget {
  const _OfflineFarmsNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.caution.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTokens.caution.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 17, color: AppTokens.caution),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Couldn't refresh the farm list — showing the farm saved on this "
              'device. Pull down to retry.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTokens.slate700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────── Farm card ──

class _FarmCard extends StatelessWidget {
  const _FarmCard({required this.farm, required this.onTap});

  final Farm farm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final logger = farm.primaryLogger;
    final loggerCount = farm.loggers.length;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8EDF3)),
          boxShadow: [
            BoxShadow(
              color: AppTokens.slate900.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Gradient cover strip ──────────────────────────────────────
            Container(
              height: 76,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF16A34A), Color(0xFF10B981)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(19)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.agriculture_rounded,
                          color: Colors.white, size: 23),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            farm.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          if (farm.location.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.place_rounded,
                                    color: Colors.white70, size: 13),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    farm.location,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          Colors.white.withValues(alpha: 0.9),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ],
                ),
              ),
            ),

            // ── Facts ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _FactTile(
                          icon: Icons.crop_square_rounded,
                          label: 'AREA',
                          value: farm.areaAcres <= 0
                              ? '—'
                              : '${_trimNum(farm.areaAcres)} acres',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _FactTile(
                          icon: Icons.grass_rounded,
                          label: 'MAIN CROP',
                          value: farm.primaryCrop.isEmpty
                              ? '—'
                              : farm.primaryCrop,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Logger installed on this farm
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: logger == null
                                ? AppTokens.slate300.withValues(alpha: 0.5)
                                : AppTokens.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            logger == null
                                ? Icons.router_outlined
                                : Icons.router_rounded,
                            color: logger == null
                                ? AppTokens.slate500
                                : AppTokens.primary,
                            size: 17,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                logger?.name ?? 'No logger installed',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                  color: AppTokens.slate900,
                                ),
                              ),
                              Text(
                                logger == null
                                    ? 'Readings unavailable for this farm'
                                    : '${logger.kind} · ${logger.deviceId}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppTokens.slate500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (loggerCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTokens.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$loggerCount LOGGER${loggerCount == 1 ? '' : 'S'}',
                              style: _labelStyle(
                                  size: 8.5, color: AppTokens.primary),
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
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppTokens.slate400),
              const SizedBox(width: 5),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _labelStyle(size: 9, color: AppTokens.slate400)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppTokens.slate900,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────── Helpers ──

String _trimNum(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

TextStyle _labelStyle({double size = 10, Color color = AppTokens.slate500}) {
  return GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: FontWeight.w900,
    color: color,
    letterSpacing: 0.9,
  );
}
