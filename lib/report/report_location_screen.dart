import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'report_draft.dart';
import 'report_summary_screen.dart';

class ReportLocationScreen extends StatefulWidget {
  final ReportDraft draft;

  const ReportLocationScreen({super.key, required this.draft});

  @override
  State<ReportLocationScreen> createState() => _ReportLocationScreenState();
}

class _ReportLocationScreenState extends State<ReportLocationScreen> {
  LatLng? _selectedLocation;

  void _onMapTap(TapPosition tapPosition, LatLng latlng) {
    setState(() {
      _selectedLocation = latlng;
    });
  }

  void _continue() {
    if (_selectedLocation == null) return;

    widget.draft.latitude = _selectedLocation!.latitude;
    widget.draft.longitude = _selectedLocation!.longitude;
    widget.draft.dateTime = DateTime.now();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportSummaryScreen(draft: widget.draft),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Where did it happen?'),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // ================= MAP =================
          FlutterMap(
            options: MapOptions(
              initialCenter: const LatLng(51.3305, -0.2708), // Epsom default
              initialZoom: 15,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              if (_selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 40,
                      height: 40,
                      point: _selectedLocation!,
                      child: const Icon(
                        Icons.location_pin,
                        size: 40,
                        color: Color(0xFFF44336),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ================= INSTRUCTION =================
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.touch_app, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedLocation == null
                          ? 'Tap on the map to select the location'
                          : 'Location selected',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ================= CONTINUE BUTTON =================
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _selectedLocation != null ? _continue : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  disabledBackgroundColor:
                      theme.colorScheme.primary.withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
