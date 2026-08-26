import 'dart:async';
import 'package:aware/report/report_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../map/map_incident.dart';
import '../theme/beeaware_theme.dart';
import 'report_labels.dart';
import 'report_step_indicator.dart';

class ReportLocationScreen extends StatefulWidget {
  final dynamic draft;
  const ReportLocationScreen({super.key, required this.draft});

  @override
  State<ReportLocationScreen> createState() => _ReportLocationScreenState();
}

class _ReportLocationScreenState extends State<ReportLocationScreen> {
  LatLng? _selectedLocation;
  LatLng? _currentLocation;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _getUserLocation();
  }

  Future<void> _getUserLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );

        final userLatLng = LatLng(position.latitude, position.longitude);

        if (mounted) {
          setState(() {
            _currentLocation = userLatLng;
            _selectedLocation = userLatLng;
          });
          _mapController.move(userLatLng, 15);
        }
      }
    } catch (e) {
      debugPrint("Erro ao localizar: $e");
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng latlng) {
    setState(() {
      _selectedLocation = latlng;
    });
  }

  void _continue() {
    if (_selectedLocation == null) return;

    // 1. Salva os dados no rascunho
    widget.draft.latitude = _selectedLocation!.latitude;
    widget.draft.longitude = _selectedLocation!.longitude;
    widget.draft.dateTime = DateTime.now();

    // 2. EXECUTA A NAVEGAÇÃO REAL
    // Certifique-se de que a ReportSummaryScreen está importada no topo do arquivo
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReportSummaryScreen(draft: widget.draft),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.whereDidItHappenTitle)),
      body: Column(
        children: [
          const ReportStepIndicator(step: 6),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(51.3305, -0.2708),
                    initialZoom: 15,
                    onTap: _onMapTap,
                  ),
                  children: [
                    // Carto's free "light_all" tiles now require an API
                    // key (see home_screen.dart's TileLayer for the full
                    // story) — switched to OpenStreetMap's own tiles as
                    // a stopgap, same as there.
                    TileLayer(
                      urlTemplate:
                          'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c'],
                      userAgentPackageName: 'io.beeaware.app',
                    ),
                    RichAttributionWidget(
                      alignment: AttributionAlignment.bottomLeft,
                      attributions: [
                        TextSourceAttribution(
                          '© OpenStreetMap contributors',
                          onTap: () => launchUrl(
                              Uri.parse('https://www.openstreetmap.org/copyright')),
                        ),
                      ],
                    ),
                    if (_currentLocation != null) _buildUserMarker(),
                    if (_selectedLocation != null) _buildSelectedMarker(),
                  ],
                ),
                Positioned(
                  right: 16,
                  bottom: 20, // Ajustado para não sobrepor o botão de baixo
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: BeeAwareTheme.surface,
                    onPressed: _getUserLocation,
                    child: const Icon(PhosphorIconsRegular.crosshair, color: Colors.blue),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: _DraftSummaryCard(draft: widget.draft),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildContinueButton(),
    );
  }

  // === MÉTODOS AUXILIARES (DENTRO DA CLASSE) ===

  Widget _buildUserMarker() => MarkerLayer(markers: [
        Marker(
          point: _currentLocation!,
          width: 30,
          height: 30,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: BeeAwareTheme.surface, width: 2),
            ),
            child: const Center(
                child: SizedBox(
                    width: 12,
                    height: 12,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: Colors.blue, shape: BoxShape.circle)))),
          ),
        ),
      ]);

  Widget _buildSelectedMarker() => MarkerLayer(markers: [
        Marker(
          point: _selectedLocation!,
          width: 45,
          height: 45,
          child: const Icon(PhosphorIconsRegular.mapPin, color: SeverityColors.high, size: 45),
        ),
      ]);

  Widget _buildContinueButton() {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final bool isSelected = _selectedLocation != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isSelected ? _continue : null,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isSelected ? BeeAwareTheme.primary : BeeAwareTheme.border,
          foregroundColor: BeeAwareTheme.textPrimary,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          elevation: 0,
        ),
        child: Text(
          isSelected ? loc.continueButton : loc.selectLocationOnMap,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
} // Chave final da classe

/// Compact reminder of what's being reported — category, subcategory and
/// severity — shown above the map so the user doesn't lose context while
/// picking the exact location.
class _DraftSummaryCard extends StatelessWidget {
  final dynamic draft;

  const _DraftSummaryCard({required this.draft});

  @override
  Widget build(BuildContext context) {
    final severity = IncidentSeverity.values.firstWhere(
      (e) => e.name == draft.severity,
      orElse: () => IncidentSeverity.low,
    );

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: BeeAwareTheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: BeeAwareTheme.border),
        boxShadow: BeeAwareTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SeverityColors.of(severity),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${ReportLabels.category(context, draft.category ?? 'Other')} '
              '→ '
              '${ReportLabels.subcategory(context, draft.subcategory ?? 'Other')}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: BeeAwareTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
