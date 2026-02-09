import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:aware/config/rounded_hexagon_painter.dart';

import '../map/map_incident.dart';
import '../map/incident_store.dart';
import '../map/bee_incident_pin.dart';
import '../report/report_category_screen.dart';
import '../theme/beeaware_theme.dart';
import 'package:geolocator/geolocator.dart';

import 'package:pwa_install/pwa_install.dart' as pwa;
import 'dart:js' as js;
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

enum IncidentTimeFilter {
  lastHour,
  last6Hours,
  last24Hours,
  all,
}

enum IncidentDistanceFilter {
  m250,
  m500,
  km1,
  all,
}

String _relativeTime(DateTime date) {
  final diff = DateTime.now().difference(date);

  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
  if (diff.inHours < 24) return '${diff.inHours} hours ago';
  return '${diff.inDays} days ago';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MapIncident> _incidents = [];
  LatLng? _userCurrentLocation;

  Marker _buildMarker(MapIncident incident) {
    double opacity = 1.0;
    if (incident.isOfficial) {
      final now = DateTime.now();

      final monthDiff = (now.year - incident.dateTime.year) * 12 +
          now.month -
          incident.dateTime.month;

      if (monthDiff == 1) opacity = 0.8;
      if (monthDiff >= 2) opacity = 0.5;
    }

    return Marker(
      key: ValueKey(incident.id),
      width: 42,
      height: 42,
      point: incident.location,
      child: Opacity(
        opacity: opacity,
        child: BeeIncidentPin(
          incident: incident,
          onTap: () => _showIncidentDetails(context, incident),
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withOpacity(0.8),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withOpacity(0.1)),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Color(0xFF4B5563),
          ),
        ),
      ],
    );
  }

  StreamSubscription<List<MapIncident>>? _subscription;
  Timer? _syncTimer;
  Timer? _boundsDebounce;

  IncidentTimeFilter _timeFilter = IncidentTimeFilter.all;
  IncidentDistanceFilter _distanceFilter = IncidentDistanceFilter.all;

  final Set<IncidentSeverity> _activeFilters = {
    IncidentSeverity.low,
    IncidentSeverity.medium,
    IncidentSeverity.high,
  };

  final MapController _mapController = MapController();

  OverlayEntry? _hintOverlay;

  // 📍 Função que tira de Epsom e vai para sua rua
  Future<void> _centerMapOnUser() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        _mapController.move(
          LatLng(position.latitude, position.longitude),
          15.0,
        );
      }
    } catch (_) {}
  }

  Future<void> _loadUserLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );

        final userLatLng = LatLng(position.latitude, position.longitude);

        if (mounted) {
          setState(() {
            _userCurrentLocation = userLatLng;
          });
          _mapController.move(userLatLng, 15);
        }
      }
    } catch (e) {
      debugPrint("Fail to find (Home): $e");
    }
  }

  void _showReportingHint() {
    if (!mounted ||
        _hintOverlay != null ||
        ModalRoute.of(context)?.isCurrent == false) return;

    _hintOverlay = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 115,
        left: 24,
        right: 24,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 800),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 15 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text("🐝 ", style: TextStyle(fontSize: 16)),
                    Flexible(
                      child: Text(
                        "Spot something? Tap the Bee.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_hintOverlay!);

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _hintOverlay != null) {
        _clearHint();
      }
    });
  }

  void _clearHint() {
    _hintOverlay?.remove();
    _hintOverlay = null;
  }

  // 📍 centro inicial
  LatLng? _initialCenter;
  static const LatLng _mapCenter = LatLng(51.3305, -0.2708);
  final Distance _distanceCalc = const Distance();

  Future<void> _resolveInitialCenter() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _initialCenter = _mapCenter);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _initialCenter = _mapCenter);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );

      final latLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _initialCenter = latLng;
      });
    } catch (_) {
      setState(() => _initialCenter = _mapCenter);
    }
  }

  @override
  void initState() {
    super.initState();

    _subscription = IncidentStore.stream.listen((data) {
      if (!mounted) return;
      setState(() => _incidents = data);
    });

    _syncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => IncidentStore.syncFromBackend(),
    );

    _loadUserLocation();
    _resolveInitialCenter();
  }

  @override
  void dispose() {
    _hintOverlay?.remove();
    _subscription?.cancel();
    _syncTimer?.cancel();
    _boundsDebounce?.cancel();
    super.dispose();
  }

  DateTime? get _lastUpdate {
    if (_incidents.isEmpty) return null;
    final sorted = List<MapIncident>.from(_incidents)
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return sorted.first.dateTime;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    debugPrint(
      'INCIDENTS total=${_incidents.length} official=${_incidents.where((i) => i.isOfficial).length} community=${_incidents.where((i) => !i.isOfficial).length}',
    );

    // ✅ FIX: Use user location / initial center for distance reference
    final LatLng distanceFrom =
        _userCurrentLocation ?? _initialCenter ?? _mapCenter;

    final visibleIncidents = _incidents.where((i) {
      if (!_activeFilters.contains(i.severity)) return false;

      // time filter applies to ALL incidents (as you requested)
      switch (_timeFilter) {
        case IncidentTimeFilter.lastHour:
          if (!i.dateTime.isAfter(now.subtract(const Duration(hours: 1)))) {
            return false;
          }
          break;
        case IncidentTimeFilter.last6Hours:
          if (!i.dateTime.isAfter(now.subtract(const Duration(hours: 6)))) {
            return false;
          }
          break;
        case IncidentTimeFilter.last24Hours:
          if (!i.dateTime.isAfter(now.subtract(const Duration(hours: 24)))) {
            return false;
          }
          break;
        case IncidentTimeFilter.all:
          break;
      }

      if (_distanceFilter != IncidentDistanceFilter.all) {
        // ✅ FIX: was _mapCenter (Epsom fixed) -> now uses distanceFrom
        final meters = _distanceCalc.as(
          LengthUnit.Meter,
          distanceFrom,
          i.location,
        );

        switch (_distanceFilter) {
          case IncidentDistanceFilter.m250:
            if (meters > 250) return false;
            break;
          case IncidentDistanceFilter.m500:
            if (meters > 500) return false;
            break;
          case IncidentDistanceFilter.km1:
            if (meters > 1000) return false;
            break;
          case IncidentDistanceFilter.all:
            break;
        }
      }

      return true;
    }).toList();

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              // ✅ FIX: initial center uses _initialCenter (not only user or Epsom)
              initialCenter: _initialCenter ?? _mapCenter,
              initialZoom: 15,
              onMapReady: () {
                _loadUserLocation(); // keep (helps web/PWA)
                Future.delayed(const Duration(seconds: 3), _showReportingHint);
              },
              onPositionChanged: (position, hasGesture) {
                if (_boundsDebounce?.isActive ?? false) return;

                _boundsDebounce = Timer(const Duration(milliseconds: 600), () {
                  final bounds = _mapController.camera.visibleBounds;
                  IncidentStore.syncOfficialForBounds(bounds);
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                tileProvider: CancellableNetworkTileProvider(),
              ),

              // BLUE DOT
              if (_userCurrentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _userCurrentLocation!,
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

              // CLUSTERS
              if (visibleIncidents.isNotEmpty)
                MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    maxClusterRadius: 48,
                    size: const Size(54, 54),
                    zoomToBoundsOnClick: true,
                    spiderfyCluster: true,
                    spiderfyCircleRadius: 80,
                    markers: visibleIncidents.map(_buildMarker).toList(),
                    builder: (context, markers) {
                      final List<Marker> markerList =
                          markers.whereType<Marker>().toList();
                      final severity = _worstSeverity(markerList);
                      final hasOfficial = _hasOfficialIncident(markerList);

                      return _AnimatedCluster(
                        count: markerList.length,
                        color: _severityColor(severity),
                        hasOfficial: hasOfficial,
                      );
                    },
                  ),
                ),
            ],
          ),

          // SEVERITY LEGEND
          Positioned(
            bottom: 110,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLegendItem(Colors.red, 'High Severity'),
                  const SizedBox(height: 4),
                  _buildLegendItem(Colors.orange, 'Medium Severity'),
                  const SizedBox(height: 4),
                  _buildLegendItem(Colors.yellow, 'Low Severity'),
                ],
              ),
            ),
          ),

          // LEFT: watermark + about
          Positioned(
            top: 16,
            left: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: 0.7,
                  child: SvgPicture.asset(
                    'assets/logo/beeaware_texto.svg',
                    width: 120,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _showAboutSheet(context),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.info_outline,
                            size: 14, color: Color(0xFF6B7280)),
                        SizedBox(width: 6),
                        Text(
                          'About BeeAware',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // RIGHT: status + disclaimer + official legend
          if (_lastUpdate != null)
            Positioned(
              top: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Latest community update · ${_lastUpdate!.hour.toString().padLeft(2, '0')}:${_lastUpdate!.minute.toString().padLeft(2, '0')}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: const Color(0xFF6B7280)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Not an emergency service',
                      style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _showOfficialLegendSheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.verified_outlined,
                              size: 14, color: Color(0xFF6B7280)),
                          SizedBox(width: 6),
                          Text(
                            'Official police data',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
// 📍 BOTÃO CENTRALIZAR NO USUÁRIO (bússola)
          Positioned(
            right: 16,
            bottom: 120, // acima da bottom bar
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              onPressed: _centerMapOnUser,
              child: const Icon(
                Icons.my_location,
                color: Colors.blue,
              ),
            ),
          ),

          // BOTTOM BAR (unchanged)
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: _BottomBar(
              onReport: () {
                _clearHint();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ReportCategoryScreen(),
                  ),
                );
              },
              onPolice: () => _showPoliceSheet(context),
              onFilters: () => _showFiltersSheet(context),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasOfficialIncident(List<Marker> markers) {
    for (final marker in markers) {
      Widget? child = marker.child;
      if (child is Opacity) child = child.child;

      if (child is BeeIncidentPin && child.incident.isOfficial) {
        return true;
      }
    }
    return false;
  }

  IncidentSeverity _worstSeverity(List<Marker> markers) {
    IncidentSeverity worst = IncidentSeverity.low;

    for (final m in markers) {
      Widget? child = m.child;

      if (child is Opacity) {
        child = child.child;
      }

      if (child is BeeIncidentPin) {
        if (child.incident.severity == IncidentSeverity.high) {
          return IncidentSeverity.high;
        }
        if (child.incident.severity == IncidentSeverity.medium) {
          worst = IncidentSeverity.medium;
        }
      }
    }
    return worst;
  }

  Color _severityColor(IncidentSeverity? s) {
    if (s == IncidentSeverity.high) return const Color(0xFFEF4444);
    if (s == IncidentSeverity.medium) return const Color(0xFFF59E0B);
    return const Color(0xFFFDE047);
  }

  // ===== bottom sheets =====

  void _showIncidentDetails(BuildContext context, MapIncident incident) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(incident.category,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(incident.subcategory,
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
            const SizedBox(height: 12),
            Text(
              incident.description.isEmpty
                  ? 'No description provided.'
                  : incident.description,
            ),
            const SizedBox(height: 12),
            Text(
              incident.isOfficial
                  ? "Official Police Record · ${incident.dateTime.month}/${incident.dateTime.year}"
                  : "Community Report · ${_relativeTime(incident.dateTime)}",
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPoliceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Emergency services',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.emergency),
                label: const Text('Call emergency (999)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF44336),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final uri = Uri.parse('tel:999');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.phone),
                label: const Text('Call non-emergency (101)'),
                onPressed: () async {
                  final uri = Uri.parse('tel:101');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'BeeAware is not an emergency service.\n'
                'If you are in immediate danger, contact emergency services directly.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFiltersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Text('Time',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...IncidentTimeFilter.values.map((f) {
                    final label = {
                      IncidentTimeFilter.lastHour: 'Last hour',
                      IncidentTimeFilter.last6Hours: 'Last 6 hours',
                      IncidentTimeFilter.last24Hours: 'Last 24 hours',
                      IncidentTimeFilter.all: 'All time',
                    }[f]!;
                    return RadioListTile<IncidentTimeFilter>(
                      title: Text(label),
                      value: f,
                      groupValue: _timeFilter,
                      onChanged: (v) {
                        setModalState(() => _timeFilter = v!);
                        setState(() {});
                      },
                    );
                  }),
                  const Divider(height: 32),
                  const Text('Distance',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...IncidentDistanceFilter.values.map((f) {
                    final label = {
                      IncidentDistanceFilter.m250: 'Within 250 m',
                      IncidentDistanceFilter.m500: 'Within 500 m',
                      IncidentDistanceFilter.km1: 'Within 1 km',
                      IncidentDistanceFilter.all: 'Any distance',
                    }[f]!;
                    return RadioListTile<IncidentDistanceFilter>(
                      title: Text(label),
                      value: f,
                      groupValue: _distanceFilter,
                      onChanged: (v) {
                        setModalState(() => _distanceFilter = v!);
                        setState(() {});
                      },
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAboutSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Center(
                          child: Text(
                            'About BeeAware',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'BeeAware is a community safety awareness platform.\n\n'
                          'It helps people share and view local, non-emergency safety-related '
                          'information to improve situational awareness and support safer '
                          'day-to-day decisions.\n\n'
                          'Reports shown in this app may come from community members or from '
                          'publicly available official data sources. These reports may be '
                          'incomplete, delayed, inaccurate, or unverified.\n\n'
                          'BeeAware does not monitor incidents in real time and is not an '
                          'emergency service.',
                          style: TextStyle(fontSize: 14, height: 1.5),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Privacy & anonymity',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'BeeAware is designed with privacy by default.\n'
                          'No personal identifying information is required.\n'
                          'Reports are anonymous and location data is limited '
                          'to what is necessary to display incidents on the map.',
                          style: TextStyle(fontSize: 14),
                        ),
                        SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  child: Column(
                    children: [
                      TextButton(
                        onPressed: () async {
                          final uri =
                              Uri.parse('https://www.getbeeaware.com/privacy');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Text('Privacy Policy'),
                      ),
                      TextButton(
                        onPressed: () async {
                          final uri =
                              Uri.parse('https://www.getbeeaware.com/terms');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Text('Terms of Service'),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '© BeeAware',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showOfficialLegendSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Center(
                child: Text(
                  'Data sources',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: 14),
              Text(
                'BeeAware shows two types of reports:\n\n'
                '• Community reports (anonymous user submissions)\n'
                '• Official open data (UK Police street-level crime data)\n\n'
                'Official items are displayed with a distinct pin. '
                'They are included for situational awareness and are not real-time emergency alerts.',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

// ================= CLUSTER =================

class _AnimatedCluster extends StatefulWidget {
  final int count;
  final Color color;
  final bool hasOfficial;

  const _AnimatedCluster({
    required this.count,
    required this.color,
    required this.hasOfficial,
  });

  @override
  State<_AnimatedCluster> createState() => _AnimatedClusterState();
}

class _AnimatedClusterState extends State<_AnimatedCluster>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..forward();

  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _intro.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_AnimatedCluster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color || oldWidget.count != widget.count) {
      _intro.reset();
      _intro.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _intro, curve: Curves.easeOutBack),
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, child) => Transform.scale(
          scale: 1.0 + (_breath.value * 0.04),
          child: child,
        ),
        child: UnconstrainedBox(
          child: CustomPaint(
            size: const Size(45, 52),
            painter: RoundedHexagonPainter(color: widget.color),
            child: SizedBox(
              width: 45,
              height: 52,
              child: Center(
                child: Text(
                  widget.count.toString(),
                  style: TextStyle(
                    color: widget.color == const Color(0xFFFDE047)
                        ? Colors.black
                        : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ================= BOTTOM BAR =================

class _BottomBar extends StatefulWidget {
  final VoidCallback onReport;
  final VoidCallback onPolice;
  final VoidCallback onFilters;

  const _BottomBar({
    required this.onReport,
    required this.onPolice,
    required this.onFilters,
  });

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  bool canInstall = false;
  Timer? _pwaTimer;

  @override
  void initState() {
    super.initState();
    canInstall = false;

    // optional: detect installability periodically
    _pwaTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      bool ok = false;

      try {
        final hasMethod = js.context.hasProperty('isPwaInstallable');
        if (hasMethod == true) {
          ok = js.context.callMethod('isPwaInstallable') == true;
        }
      } catch (_) {
        ok = false;
      }

      if (mounted && ok != canInstall) {
        setState(() => canInstall = ok);
      }
    });
  }

  @override
  void dispose() {
    _pwaTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 12,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Tooltip(
                  message: 'Emergency services',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: IconButton(
                      icon: const Icon(Icons.emergency),
                      color: const Color(0xFFF59E0B),
                      onPressed: widget.onPolice,
                    ),
                  ),
                ),
                if (canInstall)
                  Tooltip(
                    message: 'Install App',
                    child: IconButton(
                      icon: const Icon(Icons.install_mobile),
                      color: const Color(0xFFF59E0B),
                      onPressed: () {
                        if (js.context.callMethod('isPwaInstallable') == true) {
                          js.context.callMethod('triggerPwaInstall');
                        } else {
                          pwa.PWAInstall().promptInstall_();
                        }
                      },
                    ),
                  ),
                const SizedBox(width: 66),
                Tooltip(
                  message: 'Filter incidents',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: IconButton(
                      icon: const Icon(Icons.filter_list_alt),
                      color: const Color(0xFF2F3A4A),
                      onPressed: widget.onFilters,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            child: Tooltip(
              message: 'Share a local safetly report',
              child: _AnimatedCentralButton(onTap: widget.onReport),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedCentralButton extends StatefulWidget {
  final VoidCallback onTap;

  const _AnimatedCentralButton({required this.onTap});

  @override
  State<_AnimatedCentralButton> createState() => _AnimatedCentralButtonState();
}

class _AnimatedCentralButtonState extends State<_AnimatedCentralButton> {
  double _scale = 1.0;

  void _setScale(double value) {
    if (!mounted) return;
    setState(() => _scale = value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setScale(1.05),
      onExit: (_) => _setScale(1.0),
      child: GestureDetector(
        onTapDown: (_) => _setScale(0.94),
        onTapUp: (_) {
          _setScale(1.05);
          widget.onTap();
        },
        onTapCancel: () => _setScale(1.0),
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2F3A4A).withOpacity(0.10),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(5),
            child: SvgPicture.asset(
              'assets/logo/beeaware_logo.svg',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
