import 'dart:async';
import 'package:aware/report/report_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

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

    print("Summary...");

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
      appBar: AppBar(title: const Text('Where did it happen?')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(51.3305, -0.2708),
              initialZoom: 15,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
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
              backgroundColor: Colors.white,
              onPressed: _getUserLocation,
              child: const Icon(Icons.my_location, color: Colors.blue),
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
              color: Colors.blue.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Center(
                child: Icon(Icons.circle, color: Colors.blue, size: 12)),
          ),
        ),
      ]);

  Widget _buildSelectedMarker() => MarkerLayer(markers: [
        Marker(
          point: _selectedLocation!,
          width: 45,
          height: 45,
          child: const Icon(Icons.location_pin, color: Colors.red, size: 45),
        ),
      ]);

  Widget _buildContinueButton() {
    final theme = Theme.of(context);
    final bool isSelected = _selectedLocation != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isSelected ? _continue : null,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isSelected ? const Color(0xFFF59E0B) : Colors.grey[300],
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Text(
          isSelected ? 'Continue' : 'Select a location on map',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
} // Chave final da classe
