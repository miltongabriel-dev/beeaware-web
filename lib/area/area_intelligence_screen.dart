import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../backend/district_crime_api.dart';
import '../backend/historical_safety_api.dart';
import '../backend/live_awareness_api.dart';
import '../backend/recent_activity_api.dart';
import '../l10n/app_localizations.dart';
import '../theme/beeaware_theme.dart';

/// Safety Pulse (roadmap 1.2 / wireframe 9.2), reached by tapping a
/// municipality on the choropleth. Shows whatever each of the three
/// dimensions can honestly say for THIS municipality right now — a
/// dimension with no real signal renders its own "not enough data" state
/// rather than a fabricated number, same principle each backend RPC
/// already applies (see historical_safety_within_state.sql,
/// recent_activity_within_state.sql, live_awareness_rpc.sql headers).
class AreaIntelligenceScreen extends StatefulWidget {
  final String cityIbgeCode;
  final String cityName;
  final String stateCode;
  final double tapLat;
  final double tapLng;

  const AreaIntelligenceScreen({
    super.key,
    required this.cityIbgeCode,
    required this.cityName,
    required this.stateCode,
    required this.tapLat,
    required this.tapLng,
  });

  @override
  State<AreaIntelligenceScreen> createState() =>
      _AreaIntelligenceScreenState();
}

class _AreaIntelligenceScreenState extends State<AreaIntelligenceScreen> {
  static const double _liveRadiusMeters = 2000;

  bool _loading = true;
  bool _failed = false;
  HistoricalSafetyWithinState? _historical;
  RecentActivity? _recent;
  LiveAwareness? _live;
  DistrictCrime? _district;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        HistoricalSafetyApi.fetchForCity(widget.cityIbgeCode),
        RecentActivityApi.fetchForCity(widget.cityIbgeCode),
        LiveAwarenessApi.fetch(
          lat: widget.tapLat,
          lng: widget.tapLng,
          radiusMeters: _liveRadiusMeters,
        ),
        // Not municipality-level like the three above — only fills in
        // when the tap landed inside a real police-district polygon
        // (RJ's CISP, SP's DP so far). Fetched alongside the others
        // rather than gating on them succeeding first: it's an
        // independent, optional bonus section, not part of the core
        // Safety Pulse the rest of this screen depends on.
        DistrictCrimeApi.fetch(lat: widget.tapLat, lng: widget.tapLng),
      ]);

      if (!mounted) return;
      setState(() {
        _historical = results[0] as HistoricalSafetyWithinState?;
        _recent = results[1] as RecentActivity?;
        _live = results[2] as LiveAwareness?;
        _district = results[3] as DistrictCrime?;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: BeeAwareTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(cityName: widget.cityName, stateCode: widget.stateCode),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _failed
                      ? Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.all(AppSpacing.lg),
                            child: Text(
                              loc.areaIntelligenceLoadError,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: BeeAwareTheme.textSecondary,
                              ),
                            ),
                          ),
                        )
                      : _Content(
                          stateCode: widget.stateCode,
                          historical: _historical,
                          recent: _recent,
                          live: _live,
                          liveRadiusMeters: _liveRadiusMeters,
                          district: _district,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String cityName;
  final String stateCode;

  const _Header({required this.cityName, required this.stateCode});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(PhosphorIconsRegular.caretLeft,
                color: BeeAwareTheme.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cityName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: BeeAwareTheme.textPrimary,
                ),
              ),
              Text(
                stateCode,
                style: const TextStyle(
                  fontSize: 13,
                  color: BeeAwareTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  final String stateCode;
  final HistoricalSafetyWithinState? historical;
  final RecentActivity? recent;
  final LiveAwareness? live;
  final double liveRadiusMeters;
  final DistrictCrime? district;

  const _Content({
    required this.stateCode,
    required this.historical,
    required this.recent,
    required this.live,
    required this.liveRadiusMeters,
    required this.district,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final radiusLabel = '${(liveRadiusMeters / 1000).toStringAsFixed(0)}km';

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
      children: [
        Text(
          loc.areaIntelligenceSafetyPulse,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: BeeAwareTheme.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: BeeAwareTheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: BeeAwareTheme.border),
            boxShadow: BeeAwareTheme.cardShadow,
          ),
          child: Column(
            children: [
              _PulseRow(
                icon: PhosphorIconsRegular.clockCounterClockwise,
                label: loc.areaIntelligenceHistorical,
                caption: historical != null
                    ? loc.areaIntelligenceHistoricalCaption(stateCode)
                    : loc.areaIntelligenceNoData,
                score: historical?.score,
              ),
              const Divider(height: 1, color: BeeAwareTheme.border),
              _PulseRow(
                icon: PhosphorIconsRegular.trendUp,
                label: loc.areaIntelligenceRecent,
                caption: recent?.recentActivityScore != null
                    ? loc.areaIntelligenceRecentCaption
                    : loc.areaIntelligenceNoData,
                score: recent?.recentActivityScore,
              ),
              const Divider(height: 1, color: BeeAwareTheme.border),
              _PulseRow(
                icon: PhosphorIconsRegular.pulse,
                label: loc.areaIntelligenceLive,
                caption: loc.areaIntelligenceLiveCaption(radiusLabel),
                signalCount: live?.totalCount,
              ),
            ],
          ),
        ),
        if (district != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _DistrictBreakdown(district: district!),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(
          loc.areaIntelligenceDisclaimer,
          style: const TextStyle(
            fontSize: 12,
            color: BeeAwareTheme.textAux,
          ),
        ),
      ],
    );
  }
}

/// One Safety Pulse dimension. Pass either [score] (0-100, Historical/
/// Recent) or [signalCount] (Live, no score) — never both meaningfully at
/// once, matching each dimension's own honest shape (see the RPC
/// headers this mirrors).
class _PulseRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String caption;
  final int? score;
  final int? signalCount;

  const _PulseRow({
    required this.icon,
    required this.label,
    required this.caption,
    this.score,
    this.signalCount,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final hasScore = score != null;
    final hasSignalCount = signalCount != null;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BeeAwareTheme.primary.withValues(alpha: 0.08),
            ),
            child: Icon(icon, size: 18, color: BeeAwareTheme.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: BeeAwareTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: const TextStyle(
                    fontSize: 12,
                    color: BeeAwareTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (hasScore)
            _ScorePill(score: score!)
          else if (hasSignalCount)
            Text(
              loc.areaIntelligenceSignalCount(signalCount!),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: signalCount! > 0
                    ? BeeAwareTheme.textPrimary
                    : BeeAwareTheme.textAux,
              ),
            )
          else
            const Text(
              '—',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: BeeAwareTheme.textAux,
              ),
            ),
        ],
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  final int score;

  const _ScorePill({required this.score});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (score >= 66) {
      bg = SemanticColors.successSoft;
      fg = SemanticColors.successText;
    } else if (score >= 33) {
      bg = SemanticColors.alertSoft;
      fg = SemanticColors.alertText;
    } else {
      bg = SemanticColors.errorSoft;
      fg = SemanticColors.errorText;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '$score',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// Bonus section, only rendered when the tap landed inside a real police-
/// district polygon (district_crime_for_point RPC) — a finer-grained
/// look than the municipality-wide Safety Pulse above it, not a
/// replacement for it (most taps still won't have this, since only
/// RJ/SP have this geometry so far).
class _DistrictBreakdown extends StatelessWidget {
  final DistrictCrime district;

  const _DistrictBreakdown({required this.district});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.areaIntelligenceDistrictBreakdown,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: BeeAwareTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          loc.areaIntelligenceDistrictCaption(district.districtName),
          style: const TextStyle(
            fontSize: 12,
            color: BeeAwareTheme.textAux,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: BeeAwareTheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: BeeAwareTheme.border),
            boxShadow: BeeAwareTheme.cardShadow,
          ),
          child: Column(
            children: [
              _DistrictRow(
                icon: PhosphorIconsRegular.handFist,
                label: loc.areaIntelligenceDistrictViolence,
                count: district.violenceCount,
              ),
              const Divider(height: 1, color: BeeAwareTheme.border),
              _DistrictRow(
                icon: PhosphorIconsRegular.bag,
                label: loc.areaIntelligenceDistrictProperty,
                count: district.propertyCount,
              ),
              const Divider(height: 1, color: BeeAwareTheme.border),
              _DistrictRow(
                icon: PhosphorIconsRegular.shieldWarning,
                label: loc.areaIntelligenceDistrictPublicSafety,
                count: district.publicSafetyCount,
              ),
              const Divider(height: 1, color: BeeAwareTheme.border),
              _DistrictRow(
                icon: PhosphorIconsRegular.listChecks,
                label: loc.areaIntelligenceDistrictTotal,
                count: district.totalCount,
                emphasize: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DistrictRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool emphasize;

  const _DistrictRow({
    required this.icon,
    required this.label,
    required this.count,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: emphasize
                  ? BeeAwareTheme.textPrimary
                  : BeeAwareTheme.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                color: BeeAwareTheme.textPrimary,
              ),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 14,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
              color: BeeAwareTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
