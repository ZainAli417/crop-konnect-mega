import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_config.dart';
import '../services/station_data_source_factory.dart';
import '../viewmodels/station_dashboard_controller.dart';
import 'dashboard_tab.dart';
import 'dss_center_tab.dart';
import 'health_tab.dart';
import 'settings_tab.dart';
import 'trends_tab.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────

class _C {
  // Primary palette — forest botanical
  static const forest500 = Color(0xFF16A34A);

  // Semantic Mappings
  static const cyan = forest500; // Primary active/brand color
  static const emerald = forest500;
  static const amber = Color(0xFFF59E0B);

  // Neutrals — warm stone (mapped to Inks)
  static const stone950 = Color(0xFF0C0A09);
  static const stone900 = Color(0xFF1C1917);
  static const stone700 = Color(0xFF44403C);
  static const stone500 = Color(0xFF78716C);
  static const stone400 = Color(0xFFA8A29E);
  static const stone200 = Color(0xFFF1F5F9);
  static const stone100 = Color(0xFFF8FAFC);

  static const ink0 = stone950;
  static const ink1 = stone900;
  static const ink2 = stone700;
  static const ink3 = stone500;
  static const ink4 = stone400;

  // Surface
  static const canvas = Color(0xFFFFFFFF);
  static const surface0 = Color(0xFFFFFFFF);
  static const surface1 = stone100;
  static const surface2 = stone200;
  static const border = stone200;
}

class _Txt {
  static TextStyle display({
    double size = 26,
    FontWeight weight = FontWeight.w800,
    Color color = _C.ink0,
    double letterSpacing = -0.8,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  static TextStyle label({
    double size = 10,
    FontWeight weight = FontWeight.w700,
    Color color = _C.ink2,
    double letterSpacing = 1.2,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w700,
    Color color = _C.ink1,
    double? height,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height ?? 1.5,
      );
}

// ─── Nav Items ────────────────────────────────────────────────────────────────

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.short,
    this.badge,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String short; // compact label for the floating bottom bar
  final String? badge;
}

const _navItems = <_NavItem>[
  _NavItem(
    icon: Icons.grid_view_outlined,
    activeIcon: Icons.grid_view_rounded,
    label: 'Live Dashboard',
    short: 'Live',
  ),
  _NavItem(
    icon: Icons.psychology_outlined,
    activeIcon: Icons.psychology_rounded,
    label: 'DSS Center',
    short: 'DSS',
  ),
  _NavItem(
    icon: Icons.stacked_bar_chart_outlined,
    activeIcon: Icons.stacked_bar_chart,
    label: 'Data Trends',
    short: 'Trends',
  ),
  _NavItem(
    icon: Icons.favorite_outline_rounded,
    activeIcon: Icons.favorite_rounded,
    label: 'Logger Health',
    short: 'Health',
    badge: '2',
  ),
  _NavItem(
    icon: Icons.tune_outlined,
    activeIcon: Icons.tune_rounded,
    label: 'Logger Configuration',
    short: 'Setup',
  ),
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class StationDashboardScreen extends StatefulWidget {
  const StationDashboardScreen({
    super.key,
    required this.baseUrl,
    this.themeMode = ThemeMode.dark,
    this.onToggleTheme,
  });

  static const String routeName = '/dashboard';

  final String baseUrl;
  final ThemeMode themeMode;
  final VoidCallback? onToggleTheme;

  @override
  State<StationDashboardScreen> createState() => _StationDashboardScreenState();
}

class _StationDashboardScreenState extends State<StationDashboardScreen>
    with TickerProviderStateMixin {
  late StationDashboardController _controller;
  int _currentIndex = 0;
  StationDashboardController? _tabsController;
  List<Widget>? _cachedTabs;

  // Entry animation
  late AnimationController _entryCtrl;
  late Animation<double> _entryAnim;

  @override
  void initState() {
    super.initState();
    _controller = _buildController()..start();

    _entryCtrl = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _entryAnim = CurvedAnimation(
      parent: _entryCtrl,
      curve: Curves.easeOutQuart,
    );
    _entryCtrl.forward();

    // Light system UI — dark status/nav icons so battery, clock and nav
    // buttons stay visible on the near-white app background.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light, // iOS: dark icons
        statusBarIconBrightness: Brightness.dark, // Android: dark icons
        systemNavigationBarColor: Color(0xFFF6F8FB),
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  StationDashboardController _buildController() {
    return StationDashboardController(
      client: StationDataSourceFactory.create(
        mode: AppDataMode.supabase,
        baseUrl: widget.baseUrl,
        deviceId: AppConfig.deviceId,
        stationName: AppConfig.stationName,
      ),
    );
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  void _showQuickSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickSettingsSheet(
        onGoToSettings: () {
          Navigator.pop(context);
          setState(() => _currentIndex = 4);
        },
      ),
    );
  }

  List<Widget> _buildTabs() {
    final cached = _cachedTabs;
    if (cached != null && identical(_tabsController, _controller)) {
      return cached;
    }
    final tabs = <Widget>[
      DashboardTab(
        controller: _controller,
        onSettingsTap: _showQuickSettings,
      ),
      DssCenterTab(controller: _controller),
      TrendsTab(controller: _controller),
      HealthTab(controller: _controller),
      SettingsTab(
        controller: _controller,
      ),
    ];
    _tabsController = _controller;
    _cachedTabs = tabs;
    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final reading = _controller.latestReading;

        return Scaffold(
          backgroundColor: const Color(0xFFF6F8FB),
          body: FadeTransition(
            opacity: _entryAnim,
            child: SafeArea(
              child: _controller.isLoading && reading == null
                  ? const _SplashLoader()
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final tabs = _buildTabs();

                        // ── Desktop ≥ 1100 ─────────────────────────────
                        if (w >= 1100) {
                          return Row(children: [
                            _SideDrawer(
                              currentIndex: _currentIndex,
                              onTap: _onNavTap,
                              stationName:
                                  reading?.stationName ?? 'ESS Station',
                              isLive: false,
                            ),
                            Expanded(
                              child: _TabSwitcher(
                                index: _currentIndex,
                                children: tabs,
                              ),
                            ),
                          ]);
                        }

                        // ── Tablet 600–1099 ────────────────────────────
                        if (w >= 600) {
                          return Row(children: [
                            _CompactRail(
                              currentIndex: _currentIndex,
                              onTap: _onNavTap,
                              stationName: reading?.stationName ?? 'Station',
                            ),
                            Expanded(
                              child: _TabSwitcher(
                                index: _currentIndex,
                                children: tabs,
                              ),
                            ),
                          ]);
                        }

                        // ── Mobile < 600 ───────────────────────────────
                        return Column(children: [
                          Expanded(
                            child: _TabSwitcher(
                              index: _currentIndex,
                              children: tabs,
                            ),
                          ),
                          _BottomNav(
                            currentIndex: _currentIndex,
                            onTap: _onNavTap,
                          ),
                        ]);
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Tab Switcher ──────────────────────────────────────────────────────────────
// Smooth fade + very gentle scale — NO grey flash, NO jank

class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Keep every tab built and alive. Switching is then instant — no rebuild,
    // no re-running entrance animations, no jerk. Scroll positions are kept too.
    return IndexedStack(
      index: index,
      sizing: StackFit.expand,
      children: children,
    );
  }
}

// ─── Splash Loader ────────────────────────────────────────────────────────────

class _SplashLoader extends StatefulWidget {
  const _SplashLoader();

  @override
  State<_SplashLoader> createState() => _SplashLoaderState();
}

class _SplashLoaderState extends State<_SplashLoader>
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
    return Container(
      color: _C.canvas,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Glowing logo mark ────────────────────────────────────────
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
                      color:
                          _C.cyan.withValues(alpha: 0.28 + _pulse.value * 0.18),
                      blurRadius: 36,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(Icons.sensors_rounded,
                    color: Colors.white, size: 36),
              ),
            ),

            const SizedBox(height: 32),

            Text('Connecting to station…',
                style: _Txt.body(size: 14, color: _C.ink2)),

            const SizedBox(height: 20),

            // ── Cyan progress bar ────────────────────────────────────────
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  backgroundColor: _C.surface2,
                  valueColor: const AlwaysStoppedAnimation<Color>(_C.cyan),
                  minHeight: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Live Dot ─────────────────────────────────────────────────────────────────

class _LiveDot extends StatefulWidget {
  const _LiveDot({this.isLive = false});
  final bool isLive;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _ring;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat();
    _ring = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isLive ? _C.emerald : _C.ink3;
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.isLive)
            AnimatedBuilder(
              animation: _ring,
              builder: (_, __) => Container(
                width: 6 + (_ring.value * 10),
                height: 6 + (_ring.value * 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.4 * (1 - _ring.value)),
                ),
              ),
            ),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: widget.isLive
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.6), blurRadius: 6)
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom Navigation Bar (Mobile) ──────────────────────────────────────────

// Floating bottom bar — a detached pill with depth, a sliding active lozenge,
// and icons that pop & lift on selection.
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 4, 14, bottomPad + 12),
      child: Container(
        decoration: BoxDecoration(
          color: _C.surface0,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _C.border, width: 1),
          // layered shadow = floating depth
          boxShadow: [
            BoxShadow(
              color: _C.ink0.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: _C.cyan.withValues(alpha: 0.07),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(_navItems.length, (i) {
            return _BottomNavItem(
              item: _navItems[i],
              selected: i == currentIndex,
              onTap: () => onTap(i),
            );
          }),
        ),
      ),
    );
  }
}

// Active item = accent pill with icon + label in one row; inactive = icon only.
class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        padding: selected
            ? const EdgeInsets.symmetric(horizontal: 13, vertical: 9)
            : const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF16A34A), Color(0xFF10B981)],
                )
              : null,
          borderRadius: BorderRadius.circular(18),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _C.cyan.withValues(alpha: 0.38),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  selected ? item.activeIcon : item.icon,
                  color: selected ? Colors.white : _C.ink3,
                  size: 22,
                ),
                if (item.badge != null)
                  Positioned(
                    top: -5,
                    right: -7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : _C.amber,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.badge!,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: selected ? _C.cyan : Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // label only on the active item — smoothly expands the pill
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 9),
                      child: Text(
                        item.short,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Compact Navigation Rail (Tablet 600–1099) ────────────────────────────────

class _CompactRail extends StatelessWidget {
  const _CompactRail({
    required this.currentIndex,
    required this.onTap,
    required this.stationName,
  });
  final int currentIndex;
  final ValueChanged<int> onTap;
  final String stationName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      decoration: const BoxDecoration(
        color: _C.surface0,
        border: Border(right: BorderSide(color: _C.border, width: 1)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),

          // Logo mark
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF16A34A), Color(0xFF10B981)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _C.cyan.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.sensors_rounded,
                color: Colors.white, size: 22),
          ),

          const SizedBox(height: 28),

          Expanded(
            child: Column(
              children: List.generate(_navItems.length, (i) {
                final item = _navItems[i];
                final sel = i == currentIndex;
                return _RailItem(
                  item: item,
                  selected: sel,
                  onTap: () => onTap(i),
                );
              }),
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Tooltip(
              message: stationName,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _C.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _C.border),
                ),
                child: const Icon(Icons.account_circle_outlined,
                    color: _C.ink2, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem(
      {required this.item, required this.selected, required this.onTap});
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final color = sel ? _C.cyan : (_hovered ? _C.ink1 : _C.ink3);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      child: Tooltip(
        message: widget.item.label,
        preferBelow: false,
        child: MouseRegion(
          // ── FIX: instant onEnter/Exit but AnimatedContainer handles color ──
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              // ── All color changes ease over 220 ms — no grey snap ─────────
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: sel
                    ? _C.cyan.withValues(alpha: 0.11)
                    : _hovered
                        ? _C.cyan.withValues(alpha: 0.05) // ← teal, not grey
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: sel
                      ? _C.cyan.withValues(alpha: 0.28)
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        sel ? widget.item.activeIcon : widget.item.icon,
                        color: color,
                        size: 21,
                      ),
                      if (widget.item.badge != null)
                        Positioned(
                          top: -3,
                          right: -5,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: _C.amber,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: _Txt.label(
                      size: 9.5,
                      color: color,
                      weight: FontWeight.w700,
                    ),
                    child: Text(
                      widget.item.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Side Drawer (Desktop ≥ 1100) ────────────────────────────────────────────

class _SideDrawer extends StatelessWidget {
  const _SideDrawer({
    required this.currentIndex,
    required this.onTap,
    required this.stationName,
    required this.isLive,
  });
  final int currentIndex;
  final ValueChanged<int> onTap;
  final String stationName;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      decoration: const BoxDecoration(
        color: _C.surface0,
        border: Border(right: BorderSide(color: _C.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Brand header ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
            child: Row(
              children: [
                // Logo tile
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF16A34A), Color(0xFF10B981)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _C.cyan.withValues(alpha: 0.30),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.sensors_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Crop Konnect',
                          style: _Txt.display(size: 15, letterSpacing: -0.4)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _LiveDot(isLive: isLive),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              stationName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _Txt.body(
                                  size: 11.5,
                                  color: _C.ink2,
                                  weight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── Section label ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text('NAVIGATION',
                style:
                    _Txt.label(size: 9.5, color: _C.ink4, letterSpacing: 1.8)),
          ),

          // ── Nav items ──────────────────────────────────────────────────
          ...List.generate(
              _navItems.length,
              (i) => _DrawerNavItem(
                    item: _navItems[i],
                    selected: i == currentIndex,
                    onTap: () => onTap(i),
                  )),

          const Spacer(),

          // ── Footer card ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _C.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _C.border, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: _C.cyan.withValues(alpha: 0.04),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _C.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        const Icon(Icons.eco_rounded, color: _C.cyan, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Crop Konnect v1.0',
                            style: _Txt.body(
                                size: 12,
                                weight: FontWeight.w700,
                                color: _C.ink1)),
                      ],
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

// ─── Drawer Nav Item ──────────────────────────────────────────────────────────

class _DrawerNavItem extends StatefulWidget {
  const _DrawerNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DrawerNavItem> createState() => _DrawerNavItemState();
}

class _DrawerNavItemState extends State<_DrawerNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final fgCol = sel
        ? _C.cyan
        : _hovered
            ? _C.ink1
            : _C.ink2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            // ── Smooth 220 ms ease — eliminates grey snap ─────────────────
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: sel
                  ? _C.cyan.withValues(alpha: 0.10) // active teal wash
                  : _hovered
                      ? _C.cyan
                          .withValues(alpha: 0.05) // hover teal tint — NOT grey
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color:
                    sel ? _C.cyan.withValues(alpha: 0.28) : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Left accent pill
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 3,
                  height: 18,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: sel ? _C.cyan : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                                color: _C.cyan.withValues(alpha: 0.5),
                                blurRadius: 6)
                          ]
                        : null,
                  ),
                ),

                // Icon
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        sel ? widget.item.activeIcon : widget.item.icon,
                        key: ValueKey(sel),
                        color: fgCol,
                        size: 20,
                      ),
                    ),
                    if (widget.item.badge != null)
                      Positioned(
                        top: -4,
                        right: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: _C.amber,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(widget.item.badge!,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              )),
                        ),
                      ),
                  ],
                ),

                const SizedBox(width: 12),

                // Label
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: _Txt.body(
                      size: 13.5,
                      color: fgCol,
                      weight: FontWeight.w700,
                    ),
                    child: Text(widget.item.label),
                  ),
                ),

                // Active dot chip
                if (sel)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _C.cyan,
                      boxShadow: [
                        BoxShadow(
                            color: _C.cyan.withValues(alpha: 0.6),
                            blurRadius: 8),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Quick Settings Bottom Sheet ──────────────────────────────────────────────

class _QuickSettingsSheet extends StatelessWidget {
  const _QuickSettingsSheet({
    required this.onGoToSettings,
  });
  final VoidCallback onGoToSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: const BoxDecoration(
        color: _C.surface0,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: _C.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _C.ink4,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Row(
              children: [
                Text('Quick Settings', style: _Txt.display(size: 18)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _C.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: _C.border),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: _C.ink2, size: 16),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            Text('DATA ENVIRONMENT',
                style:
                    _Txt.label(size: 9.5, color: _C.ink3, letterSpacing: 1.8)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _C.surface1,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _C.border, width: 1),
              ),
              child: Row(
                children: const [
                  Icon(Icons.cloud_done_rounded, color: _C.cyan, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cloud Active',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _C.ink0,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Full settings button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: GestureDetector(
                onTap: onGoToSettings,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF16A34A), Color(0xFF10B981)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _C.cyan.withValues(alpha: 0.30),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'FULL SYSTEM SETTINGS',
                      style: _Txt.label(
                          size: 11, color: Colors.white, letterSpacing: 1.4),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Context Extensions ───────────────────────────────────────────────────────

extension DashboardColors on BuildContext {
  Color get ccSurface => _C.surface0;
  Color get ccCanvas => _C.canvas;
  Color get ccPrimary => _C.cyan;
  Color get ccPrimaryLight => _C.cyan.withValues(alpha: 0.12);
  Color get ccBorder => _C.border;
  Color get ccTextPrimary => _C.ink0;
  Color get ccTextSecondary => _C.ink2;
  Color get ccTextMuted => _C.ink3;
  Color get forest50 => _C.surface1;
  Color get forest100 => _C.surface2;
  Color get forest200 => _C.border;
  Color get forest500 => _C.cyan;
  Color get forest800 => _C.surface0;
}
