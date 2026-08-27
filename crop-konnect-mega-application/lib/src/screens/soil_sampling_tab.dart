import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/dashboard_theme.dart';
import '../models/crop_timeline.dart';
import '../models/farm.dart';
import '../models/soil_sample.dart';
import '../services/soil_probe_service.dart';
import '../services/soil_sample_repository.dart';
import '../viewmodels/station_dashboard_controller.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Soil Sampling — C-type RS-485 probe
//  Ported from Crop Konnect UNO's sampling screen: it shows the serial device
//  connection status and its live RS-485 readings, and the "Add Sample" action
//  opens a form (plot name, crop, sowing date) pre-filled with the current
//  readings. Saving writes the sample to Supabase, stamped with the selected
//  farm's id.
//
//  The workflow, validation and Modbus/GPS logic are unchanged from UNO — only
//  the presentation follows the Crop Konnect Mega design system.
// ════════════════════════════════════════════════════════════════════════════

class SoilSamplingTab extends StatefulWidget {
  const SoilSamplingTab({
    super.key,
    required this.controller,
    required this.farm,
  });

  final StationDashboardController controller;

  /// The farm this dashboard was opened for — the default sampling target.
  final Farm farm;

  @override
  State<SoilSamplingTab> createState() => _SoilSamplingTabState();
}

class _SoilSamplingTabState extends State<SoilSamplingTab> {
  final SoilSampleRepository _repository = const SoilSampleRepository();

  late final SoilProbeService _probe;

  /// Held as an id, not a [Farm], so the selection survives the farm list
  /// loading from Supabase mid-session. Resolving on read guarantees the farm
  /// stamped onto a sample is one that actually exists — a stale object would
  /// fail the `soil_samples.farm_id` foreign key on save.
  late String _selectedFarmId;

  Farm get _selectedFarm => FarmCatalog.resolve(_selectedFarmId);

  List<SoilSample> _samples = const <SoilSample>[];
  bool _isLoadingSamples = false;
  String? _samplesError;

  @override
  void initState() {
    super.initState();
    _probe = SoilProbeService();
    _selectedFarmId = widget.farm.id;
    unawaited(widget.controller.ensureCropTimelines());
    unawaited(_loadSamples());
  }

  @override
  void dispose() {
    _probe.dispose();
    super.dispose();
  }

  Future<void> _loadSamples() async {
    setState(() {
      _isLoadingSamples = true;
      _samplesError = null;
    });
    try {
      final rows = await _repository.fetchSamples(farmId: _selectedFarm.id);
      if (!mounted) return;
      setState(() {
        _samples = rows;
        _isLoadingSamples = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _samplesError = e.toString();
        _isLoadingSamples = false;
      });
    }
  }

  void _onFarmChanged(Farm farm) {
    if (farm.id == _selectedFarmId) return;
    setState(() => _selectedFarmId = farm.id);
    unawaited(_loadSamples());
  }

  Future<void> _openAddSample() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddSampleSheet(
        probe: _probe,
        controller: widget.controller,
        farm: _selectedFarm,
        repository: _repository,
      ),
    );
    if (saved == true) {
      // Pull the farm's history back so the new row shows up straight away.
      await _loadSamples();
      // Keep the DSS tab's sample picker in step with what was just captured.
      unawaited(widget.controller.loadSoilSamples());
    }
  }

  @override
  Widget build(BuildContext context) {
    // _probe drives the live readings; FarmCatalog.revision keeps the farm
    // dropdown correct once the farm list loads (the shell caches its tabs, so
    // its setState does not reach here).
    return ValueListenableBuilder<int>(
      valueListenable: FarmCatalog.revision,
      builder: (context, _, __) => AnimatedBuilder(
      animation: _probe,
      builder: (context, _) {
        return RefreshIndicator(
          onRefresh: _loadSamples,
          color: AppTokens.primary,
          backgroundColor: Colors.white,
          child: Container(
            color: const Color(0xFFF6F8FB),
            child: ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
              children: [
                const _SamplingHeader(),
                const SizedBox(height: 14),
                _FarmPickerCard(
                  farm: _selectedFarm,
                  onChanged: _onFarmChanged,
                ),
                const SizedBox(height: 14),
                _ProbeStatusCard(probe: _probe),
                const SizedBox(height: 14),
                _LiveReadingsCard(probe: _probe),
                const SizedBox(height: 14),
                _AddSampleButton(
                  enabled: _probe.hasData,
                  onTap: _openAddSample,
                ),
                const SizedBox(height: 14),
                _RecentSamplesCard(
                  samples: _samples,
                  isLoading: _isLoadingSamples,
                  error: _samplesError,
                  farm: _selectedFarm,
                ),
              ],
            ),
          ),
        );
      },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────── Header ──

class _SamplingHeader extends StatelessWidget {
  const _SamplingHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF16A34A), Color(0xFF10B981)],
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: AppTokens.primary.withValues(alpha: 0.32),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.biotech_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Soil Sampling',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  color: AppTokens.slate900,
                  letterSpacing: -0.8,
                ),
              ),
              Text(
                'C-type RS-485 probe',
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

// ────────────────────────────────────────────────────────────── Farm picker ──

class _FarmPickerCard extends StatelessWidget {
  const _FarmPickerCard({required this.farm, required this.onChanged});

  final Farm farm;
  final ValueChanged<Farm> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RECORDING AGAINST', style: _labelStyle(size: 10)),
          const SizedBox(height: 10),
          _FarmDropdown(farm: farm, onChanged: onChanged),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 14, color: AppTokens.slate500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Every sample you save is stored against this farm.',
                  style: _bodyStyle(size: 11.5, color: AppTokens.slate500),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The farm selector. Populated from [FarmCatalog] — a single farm for now, so
/// the control renders as a locked summary until more farms exist.
class _FarmDropdown extends StatelessWidget {
  const _FarmDropdown({required this.farm, required this.onChanged});

  final Farm farm;
  final ValueChanged<Farm> onChanged;

  @override
  Widget build(BuildContext context) {
    // FarmCatalog.farms is never empty. Guard the value anyway: DropdownButton
    // asserts if `value` is not among `items`, which a stale id could cause.
    final farms = FarmCatalog.farms;
    final selectedId =
        farms.any((f) => f.id == farm.id) ? farm.id : farms.first.id;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.agriculture_rounded, size: 19, color: AppTokens.primary),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedId,
                isExpanded: true,
                borderRadius: BorderRadius.circular(14),
                icon: const Icon(Icons.unfold_more_rounded,
                    size: 18, color: AppTokens.slate400),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppTokens.slate900,
                ),
                items: [
                  for (final f in farms)
                    DropdownMenuItem<String>(
                      value: f.id,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(
                            f.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _bodyStyle(size: 11, color: AppTokens.slate500),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: farms.length < 2
                    ? null
                    : (id) {
                        final next = FarmCatalog.byId(id);
                        if (next != null) onChanged(next);
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────── Probe status card ──

class _ProbeStatusCard extends StatelessWidget {
  const _ProbeStatusCard({required this.probe});

  final SoilProbeService probe;

  @override
  Widget build(BuildContext context) {
    final connected = probe.isConnected;
    final connecting = probe.isConnecting;
    final color = connected ? AppTokens.primary : AppTokens.alert;
    final deviceLabel = connected
        ? (probe.deviceName.isEmpty ? 'Probe connected' : probe.deviceName)
        : 'No probe connected';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(borderColor: color.withValues(alpha: 0.24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PulseDot(color: color, active: connected),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppTokens.slate900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      probe.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _bodyStyle(size: 12, color: AppTokens.slate500),
                    ),
                  ],
                ),
              ),
              _StatusChip(
                label: connected ? 'LIVE' : 'OFFLINE',
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: connecting
                  ? null
                  : (connected ? probe.disconnect : probe.connectToDevice),
              icon: connecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : Icon(
                      connected ? Icons.link_off_rounded : Icons.sensors_rounded,
                      size: 20,
                    ),
              label: Text(
                connecting
                    ? 'Connecting…'
                    : (connected ? 'Disconnect' : 'Connect probe'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                disabledBackgroundColor: AppTokens.slate300,
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 14.5, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A connection dot that pulses only while the probe is streaming.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncAnim();
  }

  @override
  void didUpdateWidget(covariant _PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncAnim();
  }

  void _syncAnim() {
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1).animate(_controller),
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.5),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────── Live readings card ──

class _LiveReadingsCard extends StatelessWidget {
  const _LiveReadingsCard({required this.probe});

  final SoilProbeService probe;

  static const int _metricCount = 7;

  @override
  Widget build(BuildContext context) {
    final has = probe.hasData;
    final metrics = _probeMetrics(probe);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sensors_rounded,
                  color: AppTokens.slate700, size: 20),
              const SizedBox(width: 8),
              Text('Current readings', style: _sectionTitleStyle()),
              const Spacer(),
              _StatusChip(
                label: has ? '$_metricCount/$_metricCount' : '0/$_metricCount',
                color: has ? AppTokens.primary : AppTokens.slate400,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            has ? 'Captured now from the probe' : 'Waiting for the probe…',
            style: _bodyStyle(size: 12, color: AppTokens.slate500),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final cols = (c.maxWidth / 168).floor().clamp(2, 4);
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.45,
                children: [
                  for (final m in metrics)
                    _MetricTile(metric: m, active: has),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One live probe metric.
class _ProbeMetric {
  const _ProbeMetric({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
}

List<_ProbeMetric> _probeMetrics(SoilProbeService p) {
  final has = p.hasData;
  return <_ProbeMetric>[
    _ProbeMetric(
      label: 'Nitrogen',
      value: has ? '${p.n}' : '—',
      unit: 'mg/kg',
      icon: Icons.grain_rounded,
      color: const Color(0xFF10B981),
    ),
    _ProbeMetric(
      label: 'Phosphorus',
      value: has ? '${p.p}' : '—',
      unit: 'mg/kg',
      icon: Icons.waves_rounded,
      color: const Color(0xFF8B5CF6),
    ),
    _ProbeMetric(
      label: 'Potassium',
      value: has ? '${p.k}' : '—',
      unit: 'mg/kg',
      icon: Icons.science_rounded,
      color: const Color(0xFFF97316),
    ),
    _ProbeMetric(
      label: 'Soil pH',
      value: has ? p.ph.toStringAsFixed(1) : '—',
      unit: 'pH',
      icon: Icons.opacity_rounded,
      color: const Color(0xFF0EA5E9),
    ),
    _ProbeMetric(
      label: 'Moisture',
      value: has ? p.moisture.toStringAsFixed(1) : '—',
      unit: '%',
      icon: Icons.water_drop_rounded,
      color: const Color(0xFF14B8A6),
    ),
    _ProbeMetric(
      label: 'Temperature',
      value: has ? p.temperature.toStringAsFixed(1) : '—',
      unit: '°C',
      icon: Icons.thermostat_rounded,
      color: const Color(0xFFF59E0B),
    ),
    _ProbeMetric(
      label: 'Conductivity',
      value: has ? '${p.ec}' : '—',
      unit: 'µS/cm',
      icon: Icons.electric_bolt_rounded,
      color: const Color(0xFF64748B),
    ),
  ];
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric, required this.active});

  final _ProbeMetric metric;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? metric.color : AppTokens.slate400;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active
              ? color.withValues(alpha: 0.22)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(metric.icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _labelStyle(size: 9.5, color: AppTokens.slate500),
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                metric.value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: active ? AppTokens.slate900 : AppTokens.slate400,
                  letterSpacing: -0.8,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  metric.unit,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _labelStyle(size: 9, color: AppTokens.slate400),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────── Add sample CTA ──

class _AddSampleButton extends StatelessWidget {
  const _AddSampleButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(
          enabled ? Icons.add_circle_outline_rounded : Icons.sensors_off_rounded,
          size: 21,
        ),
        label: Text(enabled ? 'Add Sample' : 'Waiting for the probe…'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTokens.primary,
          disabledBackgroundColor: AppTokens.slate300,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          minimumSize: const Size(0, 56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.plusJakartaSans(
              fontSize: 15.5, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── Recent samples ──

class _RecentSamplesCard extends StatelessWidget {
  const _RecentSamplesCard({
    required this.samples,
    required this.isLoading,
    required this.error,
    required this.farm,
  });

  final List<SoilSample> samples;
  final bool isLoading;
  final String? error;
  final Farm farm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded,
                  color: AppTokens.slate700, size: 20),
              const SizedBox(width: 8),
              Text('Recorded samples', style: _sectionTitleStyle()),
              const Spacer(),
              if (!isLoading)
                _StatusChip(
                  label: '${samples.length}',
                  color: AppTokens.primary,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            farm.name,
            style: _bodyStyle(size: 12, color: AppTokens.slate500),
          ),
          const SizedBox(height: 10),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else if (error != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppTokens.alert, size: 18),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Could not load samples: $error',
                    style: _bodyStyle(size: 12, color: AppTokens.slate500),
                  ),
                ),
              ],
            )
          else if (samples.isEmpty)
            Text(
              'No samples recorded for this farm yet. Connect the probe and '
              'tap “Add Sample”.',
              style: _bodyStyle(size: 12.5, color: AppTokens.slate500),
            )
          else
            for (final sample in samples.take(8)) _SampleRow(sample: sample),
        ],
      ),
    );
  }
}

class _SampleRow extends StatelessWidget {
  const _SampleRow({required this.sample});

  final SoilSample sample;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 9),
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
              Expanded(
                child: Text(
                  sample.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppTokens.slate900,
                  ),
                ),
              ),
              Text(
                formatSampleTimestamp(sample.timestamp),
                style: _labelStyle(size: 9.5, color: AppTokens.slate500),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MiniStat(label: 'N', value: _trimNum(sample.nitrogen)),
              _MiniStat(label: 'P', value: _trimNum(sample.phosphorus)),
              _MiniStat(label: 'K', value: _trimNum(sample.potassium)),
              _MiniStat(label: 'pH', value: sample.ph.toStringAsFixed(1)),
              _MiniStat(
                  label: 'Moist', value: '${sample.moisture.toStringAsFixed(1)}%'),
              _MiniStat(
                  label: 'Temp', value: '${sample.temperature.toStringAsFixed(1)}°'),
              _MiniStat(label: 'EC', value: _trimNum(sample.ec)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE8EDF3)),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '$label  ',
            style: _labelStyle(size: 9, color: AppTokens.slate400),
          ),
          TextSpan(
            text: value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: AppTokens.slate900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────── Add sample sheet ──

/// The capture form. Field set, validation rules and the GPS/geocoding flow are
/// carried over from Crop Konnect UNO unchanged; the sample is stamped with the
/// selected farm's id before it is written to Supabase.
class _AddSampleSheet extends StatefulWidget {
  const _AddSampleSheet({
    required this.probe,
    required this.controller,
    required this.farm,
    required this.repository,
  });

  final SoilProbeService probe;
  final StationDashboardController controller;
  final Farm farm;
  final SoilSampleRepository repository;

  @override
  State<_AddSampleSheet> createState() => _AddSampleSheetState();
}

class _AddSampleSheetState extends State<_AddSampleSheet> {
  final _formKey = GlobalKey<FormState>();
  final _plotController = TextEditingController();

  /// Kept as an id and resolved on read — see the note on
  /// `_SoilSamplingTabState._selectedFarmId`.
  late String _selectedFarmId;

  Farm get _selectedFarm => FarmCatalog.resolve(_selectedFarmId);

  CropTimeline? _selectedCrop;
  DateTime? _sowingDate;
  bool _showCropError = false;
  bool _showSowingError = false;

  Position? _position;
  String _address = '';
  String? _locationError;
  bool _isFetchingLocation = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedFarmId = widget.farm.id;
    unawaited(_fetchLocation());
  }

  @override
  void dispose() {
    _plotController.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickCrop() async {
    final crop = await showCropTimelinePicker(
      context,
      timelines: widget.controller.cropTimelines,
      selectedId: _selectedCrop?.id,
    );
    if (crop != null && mounted) {
      setState(() {
        _selectedCrop = crop;
        _showCropError = false;
      });
    }
  }

  Future<void> _pickSowingDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _sowingDate ?? now,
      // Sowing may be in the past or the (planned) future.
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 2),
      helpText: 'Sowing date',
    );
    if (picked != null && mounted) {
      setState(() {
        _sowingDate = picked;
        _showSowingError = false;
      });
    }
  }

  Future<void> _fetchLocation() async {
    setState(() {
      _isFetchingLocation = true;
      _locationError = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      var address =
          '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      try {
        final placemarks =
            await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          address = _formatPlacemark(placemarks.first);
        }
      } catch (e) {
        debugPrint('Reverse geocoding failed: $e');
      }

      if (!mounted) return;
      setState(() {
        _position = position;
        _address = address;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _locationError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  String _formatPlacemark(Placemark p) {
    final parts = <String>[
      p.name ?? '', p.street ?? '', p.locality ?? '',
      p.subAdministrativeArea ?? '', p.administrativeArea ?? '', p.country ?? '',
    ];
    final unique = <String>[];
    for (final part in parts) {
      final v = part.trim();
      if (v.isNotEmpty && !unique.contains(v)) unique.add(v);
    }
    return unique.isEmpty ? 'Unknown location' : unique.join(', ');
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;

  Future<void> _submit() async {
    final formValid = _formKey.currentState!.validate();
    final cropMissing = _selectedCrop == null;
    final sowingMissing = _sowingDate == null;
    final plotMissing = _plotController.text.trim().isEmpty;
    final locationMissing = _position == null;

    if (cropMissing || sowingMissing || plotMissing || locationMissing) {
      setState(() {
        _showCropError = cropMissing;
        _showSowingError = sowingMissing;
        if (locationMissing) {
          _locationError = 'GPS coordinates are required to record a geo-tagged sample.';
        }
      });
    }
    if (!formValid || cropMissing || sowingMissing || plotMissing || locationMissing) {
      return;
    }

    setState(() => _isSubmitting = true);
    final p = widget.probe;
    final plotName = _plotController.text.trim();
    final sample = SoilSample(
      lat: _position!.latitude,
      lng: _position!.longitude,
      farmId: _selectedFarm.id,
      farmName: plotName,
      cropName: _selectedCrop?.crop ?? '',
      cropId: _selectedCrop?.id ?? '',
      sowingDate: _sowingDate != null ? _fmtDate(_sowingDate!) : '',
      address: _address.isEmpty
          ? '${_position!.latitude.toStringAsFixed(6)}, ${_position!.longitude.toStringAsFixed(6)}'
          : _address,
      nitrogen: p.n.toDouble(),
      phosphorus: p.p.toDouble(),
      potassium: p.k.toDouble(),
      ph: p.ph,
      moisture: p.moisture,
      temperature: p.temperature,
      ec: p.ec.toDouble(),
    );

    try {
      await widget.repository.saveSample(sample);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sample saved',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
          ),
          backgroundColor: AppTokens.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: AppTokens.alert,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.probe;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTokens.slate300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppTokens.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                              Icons.assignment_turned_in_rounded,
                              color: AppTokens.primary,
                              size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Add soil sample',
                              style: _sectionTitleStyle(size: 20)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // ── Field details ───────────────────────────────────────
                    _groupCard(
                      children: [
                        _label('Farm'),
                        const SizedBox(height: 6),
                        _FarmDropdown(
                          farm: _selectedFarm,
                          onChanged: (f) =>
                              setState(() => _selectedFarmId = f.id),
                        ),
                        const SizedBox(height: 14),
                        _label('Plot / Field name'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _plotController,
                          validator: _required,
                          textInputAction: TextInputAction.next,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppTokens.slate900,
                          ),
                          decoration: _fieldDecoration(
                              'e.g. North block / Field 03', Icons.landscape_rounded),
                        ),
                        const SizedBox(height: 14),
                        _label('Crop'),
                        const SizedBox(height: 6),
                        _selector(
                          icon: Icons.grass_rounded,
                          value: _selectedCrop?.crop,
                          placeholder: 'Select crop',
                          hasError: _showCropError,
                          errorText: 'Please choose a crop',
                          onTap: _pickCrop,
                        ),
                        const SizedBox(height: 14),
                        _label('Sowing date'),
                        const SizedBox(height: 6),
                        _selector(
                          icon: Icons.event_rounded,
                          value: _sowingDate != null
                              ? formatSampleDate(_sowingDate!)
                              : null,
                          placeholder: 'Select sowing date',
                          hasError: _showSowingError,
                          errorText: 'Please choose the sowing date',
                          onTap: _pickSowingDate,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    _buildReviewSummary(),
                    const SizedBox(height: 12),

                    _buildLocation(),
                    const SizedBox(height: 12),

                    _buildReadingsPreview(p),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSubmitting || _isFetchingLocation
                            ? null
                            : _submit,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white),
                              )
                            : const Icon(Icons.cloud_upload_rounded, size: 20),
                        label: Text(_isSubmitting ? 'Saving…' : 'Save sample'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTokens.primary,
                          disabledBackgroundColor: AppTokens.slate300,
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white,
                          minimumSize: const Size(0, 54),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15)),
                          textStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 15, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// A subtle grouping container that visually clusters related form fields.
  Widget _groupCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _label(String text) =>
      Text(text.toUpperCase(), style: _labelStyle(size: 9.5));

  InputDecoration _fieldDecoration(String hint, IconData icon) =>
      InputDecoration(
        hintText: hint,
        hintStyle: _bodyStyle(size: 13.5, color: AppTokens.slate400),
        prefixIcon: Icon(icon, color: AppTokens.slate400, size: 18),
        filled: true,
        fillColor: const Color(0xFFF6F8FB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppTokens.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppTokens.alert, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppTokens.alert, width: 1.4),
        ),
      );

  Widget _selector({
    required IconData icon,
    required String? value,
    required String placeholder,
    required bool hasError,
    required String errorText,
    required VoidCallback onTap,
  }) {
    final hasValue = value != null && value.isNotEmpty;
    final borderCol = hasError
        ? AppTokens.alert
        : (hasValue
            ? AppTokens.primary.withValues(alpha: 0.45)
            : const Color(0xFFE2E8F0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 15),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FB),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: borderCol, width: 1.4),
            ),
            child: Row(
              children: [
                Icon(icon,
                    color: hasValue ? AppTokens.primary : AppTokens.slate400,
                    size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hasValue ? value : placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: hasValue ? FontWeight.w900 : FontWeight.w700,
                      color:
                          hasValue ? AppTokens.slate900 : AppTokens.slate400,
                    ),
                  ),
                ),
                const Icon(Icons.unfold_more_rounded,
                    color: AppTokens.slate400, size: 18),
              ],
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(errorText,
                style: _bodyStyle(size: 11.5, color: AppTokens.alert)),
          ),
      ],
    );
  }

  Widget _buildReviewSummary() {
    final plotName = _plotController.text.trim();
    final cropName = _selectedCrop?.crop ?? 'Not selected';
    final sowingDate = _sowingDate != null ? formatSampleDate(_sowingDate!) : 'Not selected';
    final location = _position == null
        ? 'Waiting for GPS…'
        : '${_position!.latitude.toStringAsFixed(6)}, ${_position!.longitude.toStringAsFixed(6)}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rate_review_rounded, size: 18, color: AppTokens.primary),
              const SizedBox(width: 8),
              Text('Review', style: _labelStyle(size: 10)),
            ],
          ),
          const SizedBox(height: 10),
          _reviewRow('Plot / Field', plotName.isEmpty ? 'Required' : plotName),
          _reviewRow('Crop', cropName),
          _reviewRow('Sowing date', sowingDate),
          _reviewRow('Geo-tag', location),
          if (_address.isNotEmpty) _reviewRow('Address', _address),
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: _labelStyle(size: 9, color: AppTokens.slate500)),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppTokens.slate900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocation() {
    final hasError = _locationError != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _label('Geo-tag & location')),
            TextButton.icon(
              onPressed: _isFetchingLocation ? null : _fetchLocation,
              icon: _isFetchingLocation
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded, size: 16),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(
                foregroundColor: AppTokens.primary,
                textStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: hasError
                ? AppTokens.alert.withValues(alpha: 0.06)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: hasError
                  ? AppTokens.alert.withValues(alpha: 0.35)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                hasError
                    ? Icons.error_outline_rounded
                    : Icons.location_on_rounded,
                size: 18,
                color: hasError ? AppTokens.alert : AppTokens.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isFetchingLocation
                      ? 'Fetching geo-tag…'
                      : (_locationError ??
                          (_address.isEmpty
                              ? 'Location unavailable'
                              : _address)),
                  style: _bodyStyle(
                    size: 12.5,
                    color: hasError ? AppTokens.alert : AppTokens.slate700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReadingsPreview(SoilProbeService p) {
    final items = <(String, String, String)>[
      ('N', '${p.n}', 'mg/kg'),
      ('P', '${p.p}', 'mg/kg'),
      ('K', '${p.k}', 'mg/kg'),
      ('pH', p.ph.toStringAsFixed(1), ''),
      ('Moist', p.moisture.toStringAsFixed(1), '%'),
      ('Temp', p.temperature.toStringAsFixed(1), '°C'),
      ('EC', '${p.ec}', 'µS/cm'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTokens.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sensors_rounded,
                  size: 16, color: AppTokens.primary),
              const SizedBox(width: 7),
              Text('CURRENT READINGS',
                  style: _labelStyle(size: 9.5, color: AppTokens.primary)),
              const Spacer(),
              Text('Captured now',
                  style: _labelStyle(size: 9, color: AppTokens.slate500)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in items)
                _MiniStat(
                  label: e.$1,
                  value: e.$3.isEmpty ? e.$2 : '${e.$2} ${e.$3}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────── Crop picker ──

/// Crop chooser backed by the app's bundled crop timelines (the same catalogue
/// the DSS tab uses), styled to match the rest of Crop Konnect Mega.
Future<CropTimeline?> showCropTimelinePicker(
  BuildContext context, {
  required List<CropTimeline> timelines,
  String? selectedId,
}) {
  return showModalBottomSheet<CropTimeline>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => _CropPickerSheet(
      timelines: timelines,
      selectedId: selectedId,
    ),
  );
}

class _CropPickerSheet extends StatefulWidget {
  const _CropPickerSheet({required this.timelines, this.selectedId});

  final List<CropTimeline> timelines;
  final String? selectedId;

  @override
  State<_CropPickerSheet> createState() => _CropPickerSheetState();
}

class _CropPickerSheetState extends State<_CropPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = widget.timelines;
    final filtered = _query.isEmpty
        ? all
        : all
            .where((t) => t.crop.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTokens.slate300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('Pick your crop', style: _sectionTitleStyle()),
                  const Spacer(),
                  Text('${all.length} crops', style: _labelStyle()),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search crops…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: const Color(0xFFF6F8FB),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: all.isEmpty
                    ? Center(
                        child: Text('Loading crops…',
                            style: _bodyStyle(color: AppTokens.slate500)),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final t = filtered[i];
                          final selected = t.id == widget.selectedId;
                          return InkWell(
                            borderRadius: BorderRadius.circular(13),
                            onTap: () => Navigator.pop(context, t),
                            child: Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppTokens.primary
                                        .withValues(alpha: 0.08)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: selected
                                      ? AppTokens.primary
                                          .withValues(alpha: 0.4)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: AppTokens.primary
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.grass_rounded,
                                        color: AppTokens.primary, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t.crop,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w900,
                                            color: AppTokens.slate900,
                                          ),
                                        ),
                                        Text(
                                          '${t.stages.length} stages · '
                                          '${t.totalDays} day cycle · '
                                          'sow ${t.sowWindow}',
                                          style: _bodyStyle(
                                              size: 11.5,
                                              color: AppTokens.slate500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(Icons.check_circle_rounded,
                                        color: AppTokens.primary, size: 22),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────── Shared small bits ──

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: _labelStyle(size: 9, color: color)),
    );
  }
}

// ──────────────────────────────────────────────────────────────── Helpers ──

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `12 Mar 2026`
String formatSampleDate(DateTime d) =>
    '${d.day} ${_months[d.month - 1]} ${d.year}';

/// `12 Mar · 14:05`
String formatSampleTimestamp(DateTime d) =>
    '${d.day} ${_months[d.month - 1]} · '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _trimNum(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

BoxDecoration _cardDecoration({Color? borderColor}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: borderColor ?? const Color(0xFFE8EDF3)),
    boxShadow: [
      BoxShadow(
        color: AppTokens.slate900.withValues(alpha: 0.04),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

TextStyle _labelStyle({double size = 10, Color color = AppTokens.slate500}) {
  return GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: FontWeight.w900,
    color: color,
    letterSpacing: 0.8,
  );
}

TextStyle _sectionTitleStyle({double size = 19}) {
  return GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: FontWeight.w900,
    color: AppTokens.slate900,
    letterSpacing: -0.5,
  );
}

TextStyle _bodyStyle({
  double size = 13,
  Color color = AppTokens.slate700,
  FontWeight weight = FontWeight.w700,
}) {
  return GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.45,
  );
}
