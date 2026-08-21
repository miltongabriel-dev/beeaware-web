import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
// Adicione este import para a performance do mapa
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

import '../map/map_incident.dart';
import '../map/incident_store.dart';
import '../backend/incident_api.dart';
import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../theme/beeaware_theme.dart';
import '../theme/fade_in.dart';
import 'report_draft.dart';
import 'report_icons.dart';
import 'report_labels.dart';
import '../utils/report_rate_limiter.dart';

class ReportSummaryScreen extends StatefulWidget {
  final ReportDraft draft;
  const ReportSummaryScreen({super.key, required this.draft});

  @override
  State<ReportSummaryScreen> createState() => _ReportSummaryScreenState();
}

class _ReportSummaryScreenState extends State<ReportSummaryScreen> {
  late DateTime _visibleAt;
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _visibleAt = DateTime.now().add(AppConfig.incidentVisibilityDelay);
    _remaining = _visibleAt.difference(DateTime.now());

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final diff = _visibleAt.difference(DateTime.now());
      setState(() {
        _remaining = diff.isNegative ? Duration.zero : diff;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _submitReport() async {
    if (_submitting) return;
    final loc = AppLocalizations.of(context)!;

    // 1. Validação de dados
    final lat = widget.draft.latitude;
    final lng = widget.draft.longitude;
    final cat = widget.draft.category;
    final sev = widget.draft.severity;
    final sub = widget.draft.subcategory;

    if (sub == null || sub.trim().isEmpty) {
      _toast(loc.missingSubcategory);
      return;
    }
    if (lat == null || lng == null) {
      _toast(loc.missingLocation);
      return;
    }

    setState(() => _submitting = true);

    try {
      // 2. Verificação de Rate Limit local
      final canSubmit = await ReportRateLimiter.canSubmit();
      if (!canSubmit) {
        final remaining = await ReportRateLimiter.remaining();
        _toast(loc.waitBeforeAnotherReport(remaining.inMinutes + 1));
        if (mounted) setState(() => _submitting = false);
        return;
      }

      final incident = MapIncident(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        location: LatLng(lat, lng),
        severity: IncidentSeverity.values.firstWhere(
          (e) => e.name == sev,
          orElse: () => IncidentSeverity.low,
        ),
        category: cat ?? 'Other',
        subcategory: sub,
        description: widget.draft.description ?? '',
        dateTime: DateTime.now(),
        visibleAt: _visibleAt,
      );

      // 3. Envio para o Backend (O dado vai para o mapa)
      await IncidentApi.createIncident(incident);

      // 4. Feedback local (Otimização de UI)
      await IncidentStore.addWithDelay(
          incident, AppConfig.incidentVisibilityDelay);

      // 5. MARCA RATE-LIMIT (Blindado contra QuotaExceededError)
      try {
        await ReportRateLimiter.markSubmitted();
      } catch (storageError) {
        // Se o LocalStorage falhar, apenas logamos. O envio já foi um sucesso!
        debugPrint(
            'LocalStorage full: Incident reported but rate-limit not saved.');
      }

      if (!mounted) return;

      _toast(loc.reportSubmittedSuccess);

      // Delay para o Toast ser lido
      await Future.delayed(const Duration(milliseconds: 600));

      if (mounted) {
        // Volta para a Home e limpa a pilha de telas
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      debugPrint('[ReportSummary] SUBMIT failed: $e');
      _toast(loc.submitFailed(e.toString()));
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final date = widget.draft.dateTime ?? DateTime.now();
    final lat = widget.draft.latitude;
    final lng = widget.draft.longitude;
    final severity = IncidentSeverity.values.firstWhere(
      (e) => e.name == widget.draft.severity,
      orElse: () => IncidentSeverity.low,
    );

    return Scaffold(
      appBar: AppBar(title: Text(loc.reviewReportTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FadeInUp(
                child: _SummaryCard(
                  icon: ReportIcons.subcategory(
                      widget.draft.subcategory ?? 'Other'),
                  title: loc.sectionCategory,
                  content:
                      '${ReportLabels.category(context, widget.draft.category ?? 'Other')} → '
                      '${ReportLabels.subcategory(context, widget.draft.subcategory ?? 'Other')}',
                ),
              ),
              FadeInUp(
                delay: const Duration(milliseconds: 60),
                child: _SummaryCard(
                  icon: Icons.warning_amber_outlined,
                  iconColor: SeverityColors.of(severity),
                  title: loc.sectionSeverity,
                  content:
                      SeverityColors.label(context, severity).toUpperCase(),
                ),
              ),
              FadeInUp(
                delay: const Duration(milliseconds: 120),
                child: _SummaryCard(
                  icon: Icons.description_outlined,
                  title: loc.sectionDescription,
                  content: (widget.draft.description ?? '').isEmpty
                      ? loc.noDescriptionProvided
                      : widget.draft.description!,
                ),
              ),
              FadeInUp(
                delay: const Duration(milliseconds: 180),
                child: _SummaryCard(
                  icon: Icons.event_outlined,
                  title: loc.sectionWhen,
                  content: DateFormat.yMd(locale).add_Hm().format(date),
                ),
              ),
              const SizedBox(height: 4),

              // PREVIEW DO MAPA
              FadeInUp(
                delay: const Duration(milliseconds: 240),
                child: Container(
                  height: 180,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: BeeAwareTheme.border),
                  ),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(lat ?? 51.3305, lng ?? -0.2708),
                      initialZoom: 16,
                      interactionOptions:
                          const InteractionOptions(flags: InteractiveFlag.none),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                        subdomains: const ['a', 'b', 'c', 'd'],
                        // Usando o provider performante que instalamos
                        tileProvider: CancellableNetworkTileProvider(),
                      ),
                      if (lat != null && lng != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(lat, lng),
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.location_pin,
                                  size: 40, color: Color(0xFFF44336)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // INFO DE DELAY
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: BeeAwareTheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: BeeAwareTheme.border),
                  boxShadow: BeeAwareTheme.cardShadow,
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _remaining == Duration.zero
                            ? loc.mapVisibleNow
                            : loc.mapVisibleShortly,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // BOTÃO SUBMETER
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submitReport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: BeeAwareTheme.textPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                  BeeAwareTheme.textPrimary)),
                        )
                      : Text(loc.submitReportAnonymously,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String content;

  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.content,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: BeeAwareTheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: BeeAwareTheme.border),
        boxShadow: BeeAwareTheme.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (iconColor ?? BeeAwareTheme.primary).withOpacity(0.1),
            ),
            child:
                Icon(icon, size: 18, color: iconColor ?? BeeAwareTheme.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12,
                        color: BeeAwareTheme.textSecondary,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text(content,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
