import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
// Adicione este import para a performance do mapa
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

import '../map/map_incident.dart';
import '../map/incident_store.dart';
import '../backend/incident_api.dart';
import 'report_draft.dart';
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
    _visibleAt = DateTime.now().add(const Duration(minutes: 1));
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

    // 1. Validação de dados
    final lat = widget.draft.latitude;
    final lng = widget.draft.longitude;
    final cat = widget.draft.category;
    final sev = widget.draft.severity;
    final sub = widget.draft.subcategory;

    if (sub == null || sub.trim().isEmpty) {
      _toast('Missing subcategory. Please go back.');
      return;
    }
    if (lat == null || lng == null) {
      _toast('Missing location. Please go back.');
      return;
    }

    setState(() => _submitting = true);

    try {
      // 2. Verificação de Rate Limit local
      final canSubmit = await ReportRateLimiter.canSubmit();
      if (!canSubmit) {
        final remaining = await ReportRateLimiter.remaining();
        _toast(
            'Please wait ${remaining.inMinutes + 1} minutes before sending another report.');
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
      await IncidentStore.addWithDelay(incident, const Duration(minutes: 1));

      // 5. MARCA RATE-LIMIT (Blindado contra QuotaExceededError)
      try {
        await ReportRateLimiter.markSubmitted();
      } catch (storageError) {
        // Se o LocalStorage falhar, apenas logamos. O envio já foi um sucesso!
        debugPrint(
            'LocalStorage full: Incident reported but rate-limit not saved.');
      }

      if (!mounted) return;

      _toast('Thank you! Your report was submitted successfully.');

      // Delay para o Toast ser lido
      await Future.delayed(const Duration(milliseconds: 600));

      if (mounted) {
        // Volta para a Home e limpa a pilha de telas
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      debugPrint('[ReportSummary] SUBMIT failed: $e');
      _toast('Submit failed: $e');
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = widget.draft.dateTime ?? DateTime.now();
    final lat = widget.draft.latitude;
    final lng = widget.draft.longitude;

    return Scaffold(
      appBar: AppBar(title: const Text('Review report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Category',
            content: '${widget.draft.category} → ${widget.draft.subcategory}',
          ),
          _Section(
            title: 'Severity',
            content: (widget.draft.severity ?? 'Low').toUpperCase(),
          ),
          _Section(
            title: 'Description',
            content: (widget.draft.description ?? '').isEmpty
                ? 'No description provided'
                : widget.draft.description!,
          ),
          _Section(
            title: 'When',
            content:
                '${date.day}/${date.month}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
          ),
          const SizedBox(height: 12),

          // PREVIEW DO MAPA
          SizedBox(
            height: 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
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
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.schedule,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _remaining == Duration.zero
                        ? 'This report is now visible on the map.'
                        : 'This report will appear on the map shortly.',
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
                foregroundColor: Colors.white,
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
                          valueColor: AlwaysStoppedAnimation(Colors.white)),
                    )
                  : const Text('Submit report anonymously',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String content;
  const _Section({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(content,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }
}
