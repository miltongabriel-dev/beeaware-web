import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../map/map_incident.dart';
import '../map/incident_store.dart';
import '../map/bee_incident_pin.dart';
import '../report/report_category_screen.dart';
import '../theme/beeaware_theme.dart';
import 'package:geolocator/geolocator.dart';

import 'package:pwa_install/pwa_install.dart' as pwa;

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

      setState(() {
        _initialCenter = LatLng(
          position.latitude,
          position.longitude,
        );
      });
    } catch (_) {
      // fail-safe absoluto
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

    // 📍 resolve localização inicial
    _resolveInitialCenter();
  }

  @override
  void dispose() {
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

    final visibleIncidents = _incidents.where((i) {
      if (!_activeFilters.contains(i.severity)) return false;

      switch (_timeFilter) {
        case IncidentTimeFilter.lastHour:
          if (!i.dateTime.isAfter(now.subtract(const Duration(hours: 1))))
            return false;
          break;
        case IncidentTimeFilter.last6Hours:
          if (!i.dateTime.isAfter(now.subtract(const Duration(hours: 6))))
            return false;
          break;
        case IncidentTimeFilter.last24Hours:
          if (!i.dateTime.isAfter(now.subtract(const Duration(hours: 24))))
            return false;
          break;
        case IncidentTimeFilter.all:
          break;
      }

      if (_distanceFilter != IncidentDistanceFilter.all) {
        final meters = _distanceCalc.as(
          LengthUnit.Meter,
          _mapCenter,
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
              initialCenter: _initialCenter ?? _mapCenter,
              initialZoom: 14,
              onMapReady: () {
                final bounds = _mapController.camera.visibleBounds;
                if (_mapController.camera.zoom >= 13) {
                  IncidentStore.syncOfficialForBounds(bounds);
                }
              },
              onPositionChanged: (position, hasGesture) {
                if (!hasGesture) return;
                if (position.zoom < 13) return;

                final bounds = _mapController.camera.visibleBounds;

                _boundsDebounce?.cancel();
                _boundsDebounce = Timer(const Duration(milliseconds: 600), () {
                  IncidentStore.syncOfficialForBounds(bounds);
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
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
                      final severity = _worstSeverity(markers);
                      final hasOfficial = _hasOfficialIncident(markers);

                      return _AnimatedCluster(
                        count: markers.length,
                        color: _severityColor(severity),
                        hasOfficial: hasOfficial,
                      );
                    },
                  ),
                ),
            ],
          ),

          // 🐝 watermark
          Positioned(
            top: 16,
            left: 16,
            child: Opacity(
              opacity: 0.45,
              child: SvgPicture.asset(
                'assets/logo/beeaware_watermark.svg',
                width: 120,
              ),
            ),
          ),

          // 🕒 latest update + about
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
                      'Latest community update · '
                      '${_lastUpdate!.hour.toString().padLeft(2, '0')}:${_lastUpdate!.minute.toString().padLeft(2, '0')}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Opacity(
                    opacity: 0.45,
                    child: Text(
                      'Not an emergency service',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _showAboutSheet(context),
                    child: Opacity(
                      opacity: 0.55,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.info_outline,
                              size: 14, color: Color(0xFF6B7280)),
                          SizedBox(width: 4),
                          Text(
                            'About BeeAware',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _showOfficialLegendSheet(context),
                    child: Opacity(
                      opacity: 0.55,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.verified_outlined,
                              size: 14,
                              color: Color(0xFF6B7280),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Includes official police data',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ⬇️ bottom bar
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: _BottomBar(
              onReport: () {
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
      final child = marker.child;
      if (child is BeeIncidentPin && child.incident.isOfficial) {
        return true;
      }
    }
    return false;
  }

  Marker _buildMarker(MapIncident incident) {
    return Marker(
      key: ValueKey(incident.id),
      width: 42,
      height: 42,
      point: incident.location,
      child: BeeIncidentPin(
        incident: incident,
        onTap: () => _showIncidentDetails(context, incident),
      ),
    );
  }

  IncidentSeverity _worstSeverity(List<Marker> markers) {
    IncidentSeverity worst = IncidentSeverity.low;
    for (final m in markers) {
      final child = m.child;
      if (child is BeeIncidentPin) {
        if (child.incident.severity == IncidentSeverity.high)
          return IncidentSeverity.high;
        if (child.incident.severity == IncidentSeverity.medium)
          worst = IncidentSeverity.medium;
      }
    }
    bool _hasOfficialIncident(List<Marker> markers) {
      for (final marker in markers) {
        final child = marker.child;
        if (child is BeeIncidentPin && child.incident.isOfficial) {
          return true;
        }
      }
      return false;
    }

    return worst;
  }

  Color _severityColor(IncidentSeverity s) {
    switch (s) {
      case IncidentSeverity.low:
        return BeeAwareTheme.severityLow;
      case IncidentSeverity.medium:
        return BeeAwareTheme.severityMedium;
      case IncidentSeverity.high:
        return BeeAwareTheme.severityHigh;
    }
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
              _relativeTime(incident.dateTime),
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
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

              // 🚨 EMERGÊNCIA — 999
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

              // ☎️ NÃO EMERGÊNCIA — 101
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

              // ⚠️ DISCLAIMER
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
                  // ── TIME FILTER ──
                  const Text(
                    'Time',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
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
                        setState(() {}); // 🔁 atualiza o mapa
                      },
                    );
                  }),

                  const Divider(height: 32),

                  // ── DISTANCE FILTER ──
                  const Text(
                    'Distance',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
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
                        setState(() {}); // 🔁 atualiza o mapa
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
                // ── drag handle ──
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

                // ── conteúdo scrollável ──
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

                // ── footer fixo ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  child: Column(
                    children: [
                      TextButton(
                        onPressed: () {
                          launchUrl(
                            Uri.parse(
                              'https://miltongabriel-dev.github.io/beeaware/privacy.html',
                            ),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        child: const Text('Privacy Policy'),
                      ),
                      TextButton(
                        onPressed: () {
                          launchUrl(
                            Uri.parse(
                              'https://miltongabriel-dev.github.io/beeaware/terms.html',
                            ),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        child: const Text('Terms of Service'),
                      ),
                      const SizedBox(height: 8),
                      const Text(
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
    duration: const Duration(milliseconds: 220),
  )..forward();

  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  late final Animation<double> _introScale = CurvedAnimation(
    parent: _intro,
    curve: Curves.easeOutBack,
  );

  @override
  void dispose() {
    _intro.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: 54,
        child: ClipRect(
          child: ScaleTransition(
            scale: _introScale,
            child: AnimatedBuilder(
              animation: _breath,
              builder: (context, child) {
                final s = 1.0 + (_breath.value * 0.03);
                return Transform.scale(
                  scale: s,
                  alignment: Alignment.center,
                  child: child,
                );
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    painter: _HexagonPainter(widget.color),
                    child: const Center(child: _ClusterText()),
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

class _ClusterText extends StatelessWidget {
  const _ClusterText();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_AnimatedClusterState>();
    final count = state?.widget.count ?? 0;

    return Text(
      count.toString(),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 18, // levemente maior, fica mais elegante
        height: 1.0,
      ),
    );
  }
}

class _HexagonPainter extends CustomPainter {
  final Color color;
  _HexagonPainter(this.color);

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final paint = Paint()..color = color;
    final w = size.width;
    final h = size.height;

    final path = ui.Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.25)
      ..lineTo(w, h * 0.75)
      ..lineTo(w * 0.5, h)
      ..lineTo(0, h * 0.75)
      ..lineTo(0, h * 0.25)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ================= BOTTOM BAR =================

class _BottomBar extends StatelessWidget {
  final VoidCallback onReport;
  final VoidCallback onPolice;
  final VoidCallback onFilters;

  const _BottomBar({
    required this.onReport,
    required this.onPolice,
    required this.onFilters,
  });

  @override
  Widget build(BuildContext context) {
    bool canInstall = pwa.PWAInstall().installPromptEnabled;

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
                      onPressed: onPolice,
                    ),
                  ),
                ),
                if (canInstall)
                  Tooltip(
                    message: 'Install App',
                    child: IconButton(
                      icon: const Icon(Icons.install_mobile),
                      color: const Color(0xFFF59E0B),
                      onPressed: () => pwa.PWAInstall().promptInstall_(),
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
                      onPressed: onFilters,
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
              child: _AnimatedCentralButton(onTap: onReport),
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
