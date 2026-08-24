import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:aware/config/rounded_hexagon_painter.dart';

import '../map/map_incident.dart';
import '../map/incident_store.dart';
import '../map/bee_incident_pin.dart';
import '../config/app_config.dart';
import '../theme/beeaware_theme.dart';
import '../theme/bee_loader.dart';
import '../report/report_category_screen.dart';
import '../report/report_labels.dart';
import '../l10n/app_localizations.dart';
import '../state/locale_state.dart';
import '../theme/fade_in.dart';
import '../utils/relative_time.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aware/auth/login_screen.dart';

import 'package:pwa_install/pwa_install.dart' as pwa;
import 'dart:js' as js;
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'widgets/incident_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:aware/state/token_state.dart';
import 'package:aware/report/buy_tokens_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:aware/home/widgets/safety_trend_chart.dart';
import 'package:aware/backend/uk_police_api.dart';
import 'package:aware/backend/brazil_crime_summary_api.dart';
import 'package:aware/backend/location_coverage_api.dart';
import '../map/municipality_choropleth_layer.dart';

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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MapIncident> _incidents = [];
  List<MunicipalityCrimeSummary> _crimeSummary = [];
  List<LocationCoverage> _coverage = [];
  LatLng? _userCurrentLocation;
  bool _isLoadingIncidents = true;
  LatLng? _searchLocation;
  bool _isSearching = false;
  bool _showLowTokenWarning = false;
  bool _showZeroTokenBanner = false;

  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;

  final Map<String, List<Map<String, dynamic>>> _searchCache = {};

  String _preferredCountryCode() {
    if (_userCurrentLocation == null) return 'gb';

    final lat = _userCurrentLocation!.latitude;

    // 🇬🇧 UK approx
    if (lat > 49 && lat < 61) return 'gb';

    // 🇧🇷 Brazil approx
    if (lat < 5 && lat > -35) return 'br';

    return 'gb';
  }

  final List<LatLng> _recentSearches = [];

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
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => IncidentBottomSheet(incident: incident),
            );
          },
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
            color: color.withValues(alpha: 0.8),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: BeeAwareTheme.textSecondary,
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

    if (_userCurrentLocation != null) {
      UkPoliceApi.refreshTrendBackground(
        lat: _userCurrentLocation!.latitude,
        lng: _userCurrentLocation!.longitude,
      );
    }
  }

  void _showReportingHint() {
    if (!mounted ||
        _hintOverlay != null ||
        ModalRoute.of(context)?.isCurrent == false) return;

    _hintOverlay = OverlayEntry(
      builder: (context) => Positioned(
        // 220 em vez de 115: a caixa da legenda de severidade (mais abaixo
        // nesse mesmo Stack) ocupa de bottom:110 até ~bottom:210 — com 115
        // esse aviso ficava por cima da legenda, cortando a linha "Cluster
        // numbers explained".
        bottom: 220,
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
                  color: BeeAwareTheme.accent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("🐝 ", style: TextStyle(fontSize: 16)),
                    Flexible(
                      child: Text(
                        AppLocalizations.of(context)!.reportingHintText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
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

  Future<void> _fetchSuggestions(String query) async {
    if (query.length < 3) {
      setState(() => _suggestions = []);
      return;
    }

    setState(() => _isSearching = true);

    try {
      final url = Uri.parse(
        'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/geocode?q=${Uri.encodeComponent(query)}&limit=5',
      );

      final response = await http.get(url);

      if (response.statusCode != 200) {
        setState(() => _isSearching = false);
        return;
      }

      final results = List<Map<String, dynamic>>.from(
        json.decode(response.body),
      );

      if (!mounted) return;

      setState(() {
        _isSearching = false;
        _suggestions = results;
      });
    } catch (e) {
      debugPrint('Autocomplete error: $e');
      setState(() => _isSearching = false);
    }
  }

  @override
  @override
  void initState() {
    super.initState();

    // 🔥 STREAM de incidentes (real-time)
    _subscription = IncidentStore.stream.listen((data) {
      if (!mounted) return;
      setState(() => _incidents = data);
    });

    // 🔥 Sync periódico (community)
    _syncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => IncidentStore.syncFromBackend(force: true),
    );

    // 🔥 Primeiro carregamento rápido
    Future.microtask(() async {
      await IncidentStore.syncFromBackend(force: true);

      if (mounted) {
        setState(() => _isLoadingIncidents = false);
      }
    });

    // 🔥 Localização do usuário
    _loadUserLocation();

    // 🔥 Centro inicial do mapa
    _resolveInitialCenter();

    // 🔥 Violência/crime por município (Brasil) — carregado uma vez,
    // não depende do viewport como os pins (dataset pequeno: dezenas de
    // municípios, não milhares de pontos).
    BrazilCrimeSummaryApi.fetchSummary().then((summary) {
      if (mounted) setState(() => _crimeSummary = summary);
    });

    // 🔥 TREND carregado em background (UX premium)
    Future.microtask(() async {
      await _loadUserLocation();

      if (_userCurrentLocation != null) {
        await UkPoliceApi.fetchTrend(
          lat: _userCurrentLocation!.latitude,
          lng: _userCurrentLocation!.longitude,
        );
      }
    });

    // 🔥 Cobertura de dados perto do usuário (BeeAware Global blueprint —
    // "Never equate 'no data' with 'safe'"). Carregado uma vez ao redor da
    // localização inicial, como o crime summary — não depende do viewport.
    Future.microtask(() async {
      await _loadUserLocation();
      final center = _userCurrentLocation;
      if (center == null) return;

      final coverage = await LocationCoverageApi.fetchCoverage(
        lat: center.latitude,
        lng: center.longitude,
        countryCode: _preferredCountryCode().toUpperCase(),
      );

      if (mounted) setState(() => _coverage = coverage);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _clearHint();
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

              // Violência/crime por município (Brasil) — abaixo dos pins,
              // acima do mapa base.
              MunicipalityChoroplethLayer(summaries: _crimeSummary),

              //Pin temporario search
              if (_searchLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _searchLocation!,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: BeeAwareTheme.accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          PhosphorIconsRegular.mapPin,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
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
                          color: Colors.blue.withValues(alpha: 0.2),
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

// ================= LOADING OVERLAY =================
          if (_isLoadingIncidents)
            Positioned.fill(
              child: Container(
                color: Colors.white.withValues(alpha: 0.55),
                child: BeeLoadingCard(
                  message: AppLocalizations.of(context)!.loadingIncidents,
                ),
              ),
            ),

          // ================= EMPTY STATE =================
          if (!_isLoadingIncidents && visibleIncidents.isEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.lg,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: BeeAwareTheme.border),
                      boxShadow: BeeAwareTheme.cardShadow,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsRegular.magnifyingGlass,
                            size: 28, color: BeeAwareTheme.textAux),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          AppLocalizations.of(context)!.noIncidentsForFilters,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: BeeAwareTheme.textSecondary,
                          ),
                        ),
                        // "No incidents" here doesn't mean "safe" — it
                        // often just means BeeAware's only signal for this
                        // area is the coarse global baseline, not a local
                        // police feed. Say so rather than staying silent.
                        if (_coverage.isNotEmpty &&
                            _coverage.every((c) => c.isCountryOnly)) ...[
                          const SizedBox(height: 6),
                          Text(
                            AppLocalizations.of(context)!
                                .coverageGlobalBaselineOnly,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              color: BeeAwareTheme.textAux,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // SEVERITY LEGEND
          Positioned(
            bottom: 110,
            left: 16,
            child: FadeInUp(
              delay: const Duration(milliseconds: 200),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLegendItem(
                        SeverityColors.high,
                        SeverityColors.labelSuffixed(
                            context, IncidentSeverity.high)),
                    const SizedBox(height: 4),
                    _buildLegendItem(
                        SeverityColors.medium,
                        SeverityColors.labelSuffixed(
                            context, IncidentSeverity.medium)),
                    const SizedBox(height: 4),
                    _buildLegendItem(
                        SeverityColors.low,
                        SeverityColors.labelSuffixed(
                            context, IncidentSeverity.low)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: _showClusterInfo,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(PhosphorIconsRegular.info,
                              size: 14, color: BeeAwareTheme.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            AppLocalizations.of(context)!
                                .clusterNumbersExplained,
                            style: const TextStyle(
                                fontSize: 11, color: BeeAwareTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    // Blueprint principle again ("never equate 'no data'
                    // with 'safe'"), applied to the municipality choropleth
                    // specifically: it only paints municipalities that HAVE
                    // a source (municipality_choropleth_layer.dart) — most
                    // of Brazil's states still have no adapter at all, so
                    // silence on the map there means "no public data", not
                    // "no crime". Only shown when the choropleth is
                    // actually rendering something, same guard as the layer
                    // itself uses.
                    if (_crimeSummary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: _showChoroplethLegendInfo,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(PhosphorIconsRegular.info,
                                size: 14, color: BeeAwareTheme.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              AppLocalizations.of(context)!
                                  .choroplethLegendTooltip,
                              style: const TextStyle(
                                  fontSize: 11, color: BeeAwareTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
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
                  child: Image.asset(
                    Localizations.localeOf(context).languageCode == 'pt'
                        ? 'assets/logo/beeaware_wordmark_pt.png'
                        : 'assets/logo/beeaware_wordmark_en.png',
                    width: 120,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // Search bar
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: FadeInUp(
              child: Builder(
                builder: (context) {
                  final tokens = context.watch<TokenState>().tokens;

                  return Container(
                    height: 58,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // MENU (☰)
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => _openMenu(context),
                            child: const Icon(
                              PhosphorIconsRegular.list,
                              size: 22,
                              color: BeeAwareTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _isSearching
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : SvgPicture.asset(
                                  'assets/icons/nearby.svg',
                                  key: const ValueKey('search_icon'),
                                  width: 20,
                                  height: 20,
                                  colorFilter: const ColorFilter.mode(
                                    BeeAwareTheme.textSecondary,
                                    BlendMode.srcIn,
                                  ),
                                ),
                        ),

                        const SizedBox(width: 16),

                        // Placeholder
                        Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              // Texto mais curto que o original ("Enter
                              // address and press search") -- o espaço
                              // disponível ao lado do ícone de busca e do
                              // badge de tokens é estreito, e a frase
                              // inteira ficava cortada no meio.
                              hintText: AppLocalizations.of(context)!
                                  .searchAnAddressHint,
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            textInputAction: TextInputAction.search,
                            onChanged: (value) {
                              _debounce?.cancel();
                              _debounce = Timer(
                                const Duration(milliseconds: 250),
                                () => _fetchSuggestions(value),
                              );
                            },
                            onSubmitted: (value) {
                              _clearHint();
                              _handleSearch(context, value);
                            },
                          ),
                        ),

                        // Tokens badge
                        if (AppConfig.tokensEnabled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: BeeAwareTheme.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              AppLocalizations.of(context)!
                                  .tokensSearchBadge(tokens),
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
                },
              ),
            ),
          ),
          if (_suggestions.isNotEmpty)
            Positioned(
              top: 120,
              left: 20,
              right: 20,
              child: Material(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                elevation: 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _suggestions[index];
                      final display = item['display_name'] ?? '';

                      return ListTile(
                        leading: const Icon(PhosphorIconsRegular.mapPin),
                        title: Text(
                          display,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          setState(() => _suggestions = []);
                          _clearHint();
                          _handleSearch(context, display);
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          if (_showLowTokenWarning)
            Positioned(
              top: 125,
              left: 30,
              right: 30,
              child: AnimatedOpacity(
                opacity: 1,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: SemanticColors.alertSoft,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.oneSearchRemaining,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SemanticColors.alertText,
                    ),
                  ),
                ),
              ),
            ),
          if (_showZeroTokenBanner)
            Positioned(
              top: 125,
              left: 30,
              right: 30,
              child: AnimatedOpacity(
                opacity: 1,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: SemanticColors.errorSoft,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    boxShadow: BeeAwareTheme.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)!.allSearchesUsed,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: SemanticColors.errorText,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BuyTokensScreen(),
                            ),
                          );
                        },
                        child: Text(AppLocalizations.of(context)!.buyMore),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Tendência, filtro e badge de cobertura agora moram na barra
          // inferior (ver _BottomBar) — ancorados junto com emergência e
          // instalar, no padrão Waze/Maps, em vez de flutuando soltos aqui.

// 📍 BOTÃO CENTRALIZAR NO USUÁRIO (bússola)
          Positioned(
            right: 16,
            bottom: 120, // acima da bottom bar
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              onPressed: _centerMapOnUser,
              child: const Icon(
                PhosphorIconsRegular.crosshair,
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
              onFilters: () => _showFiltersOverlay(),
              onTrend: _showSafetyTrend,
              onCoverageTap: () => _showCoverageSheet(context),
              coverageGrade:
                  _coverage.isNotEmpty ? (bestCoverageGrade(_coverage) ?? 'C') : null,
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

  Color _severityColor(IncidentSeverity? s) =>
      SeverityColors.of(s ?? IncidentSeverity.low);

  // ===== bottom sheets =====

  void _showIncidentDetails(BuildContext context, MapIncident incident) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) {
        final loc = AppLocalizations.of(sheetContext)!;
        final categoryLabel = incident.isOfficial
            ? loc.policeReportCategory
            : ReportLabels.category(sheetContext, incident.category);

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(categoryLabel,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(ReportLabels.subcategory(sheetContext, incident.subcategory),
                  style:
                      const TextStyle(fontSize: 14, color: BeeAwareTheme.textSecondary)),
              const SizedBox(height: 12),
              Text(
                incident.description.isEmpty
                    ? loc.noDescriptionProvided
                    : incident.description,
              ),
              const SizedBox(height: 12),
              Text(
                incident.isOfficial
                    ? loc.officialRecordDate(
                        incident.dateTime.month, incident.dateTime.year)
                    : loc.communityReportRelative(
                        relativeTime(sheetContext, incident.dateTime)),
                style: TextStyle(
                  fontSize: 12,
                  color: BeeAwareTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showClusterInfo() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) {
        final loc = AppLocalizations.of(sheetContext)!;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                loc.clusterCountTitle,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Text(
                loc.clusterCountExplanation,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showChoroplethLegendInfo() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) {
        final loc = AppLocalizations.of(sheetContext)!;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                loc.choroplethLegendTitle,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 12),
              _buildLegendItem(SeverityColors.high,
                  SeverityColors.labelSuffixed(sheetContext, IncidentSeverity.high)),
              const SizedBox(height: 6),
              _buildLegendItem(SeverityColors.medium,
                  SeverityColors.labelSuffixed(sheetContext, IncidentSeverity.medium)),
              const SizedBox(height: 6),
              _buildLegendItem(SeverityColors.low,
                  SeverityColors.labelSuffixed(sheetContext, IncidentSeverity.low)),
              const SizedBox(height: 16),
              Text(
                loc.choroplethNoDataDisclaimer,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: BeeAwareTheme.textSecondary),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showPoliceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) {
        final loc = AppLocalizations.of(sheetContext)!;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.emergencyServices,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(PhosphorIconsRegular.siren),
                label: Text(loc.callEmergency999),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SeverityColors.high,
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
                icon: const Icon(PhosphorIconsRegular.phone),
                label: Text(loc.callNonEmergency101),
                onPressed: () async {
                  final uri = Uri.parse('tel:101');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
              ),
              const SizedBox(height: 12),
              Text(
                loc.emergencyDisclaimer,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: BeeAwareTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  OverlayEntry? _filterOverlay;

  void _showFiltersOverlay() {
    if (!mounted) return;

    if (_filterOverlay != null) {
      _filterOverlay!.remove();
      _filterOverlay = null;
    }

    _filterOverlay = OverlayEntry(
      builder: (context) {
        return GestureDetector(
          onTap: () {
            if (_filterOverlay != null) {
              _filterOverlay!.remove();
              _filterOverlay = null;
            }
          },
          child: Material(
            color: Colors.black.withValues(alpha: 0.25),
            child: Center(
              child: GestureDetector(
                onTap: () {}, // evita fechar ao clicar dentro
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 250),
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: 0.95 + (0.05 * value),
                      child: Opacity(opacity: value, child: child),
                    );
                  },
                  child: Container(
                    width: 380,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: _buildFiltersContent(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_filterOverlay!);
  }

  Widget _buildFiltersContent() {
    return StatefulBuilder(
      builder: (context, setModalState) {
        final loc = AppLocalizations.of(context)!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              loc.filters,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(loc.filterTimeSectionTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            ...IncidentTimeFilter.values.map((f) {
              final label = {
                IncidentTimeFilter.lastHour: loc.timeFilterLastHour,
                IncidentTimeFilter.last6Hours: loc.timeFilterLast6Hours,
                IncidentTimeFilter.last24Hours: loc.timeFilterLast24Hours,
                IncidentTimeFilter.all: loc.timeFilterAllTime,
              }[f]!;

              return RadioListTile<IncidentTimeFilter>(
                dense: true,
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
            Align(
              alignment: Alignment.centerLeft,
              child: Text(loc.distanceLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            ...IncidentDistanceFilter.values.map((f) {
              final label = {
                IncidentDistanceFilter.m250: loc.distanceFilter250m,
                IncidentDistanceFilter.m500: loc.distanceFilter500m,
                IncidentDistanceFilter.km1: loc.distanceFilter1km,
                IncidentDistanceFilter.all: loc.distanceFilterAny,
              }[f]!;

              return RadioListTile<IncidentDistanceFilter>(
                dense: true,
                title: Text(label),
                value: f,
                groupValue: _distanceFilter,
                onChanged: (v) {
                  setModalState(() => _distanceFilter = v!);
                  setState(() {});
                },
              );
            }),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => _filterOverlay?.remove(),
              child: Text(loc.close),
            ),
          ],
        );
      },
    );
  }

  void _showAboutSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) {
        final loc = AppLocalizations.of(sheetContext)!;
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
                    color: BeeAwareTheme.border,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Text(
                            loc.aboutBeeAware,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        Text(
                          loc.aboutBodyText,
                          style: const TextStyle(fontSize: 14, height: 1.5),
                        ),

                        const SizedBox(height: 20),

                        // 🔥 NOVA SEÇÃO
                        Text(
                          loc.dataSources,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),

                        Text(
                          loc.aboutDataSourcesBody,
                          style: const TextStyle(fontSize: 14),
                        ),

                        const SizedBox(height: 20),

                        Text(
                          loc.privacyAnonymityTitle,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),

                        Text(
                          loc.privacyAnonymityBody,
                          style: const TextStyle(fontSize: 14),
                        ),

                        const SizedBox(height: 24),
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
                              Uri.parse('https://www.beeaware.io/privacy.html');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Text(loc.privacyPolicyButton),
                      ),
                      TextButton(
                        onPressed: () async {
                          final uri =
                              Uri.parse('https://www.beeaware.io/terms.html');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Text(loc.termsOfServiceButton),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        loc.copyrightBeeAware,
                        style: const TextStyle(
                          fontSize: 12,
                          color: BeeAwareTheme.textSecondary,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) {
        final loc = AppLocalizations.of(sheetContext)!;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  loc.dataSources,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                loc.officialLegendBody,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  String _coverageCategoryLabel(AppLocalizations loc, String eventCategory) {
    switch (eventCategory) {
      case 'VIOLENCE':
        return loc.coverageCategoryViolence;
      case 'PROPERTY':
        return loc.coverageCategoryProperty;
      case 'PUBLIC_SAFETY':
        return loc.coverageCategoryPublicSafety;
      case 'ROAD_SAFETY':
        return loc.coverageCategoryRoadSafety;
      default:
        return eventCategory;
    }
  }

  // Wireframe 8.4 "Explain — score provenance" from the BeeAware Global
  // blueprint: show what's actually behind the badge instead of a bare
  // letter — source, freshness, geography — so a coarse grade never reads
  // as untrustworthy silence.
  void _showCoverageSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) {
        final loc = AppLocalizations.of(sheetContext)!;
        final coverage = List<LocationCoverage>.from(_coverage)
          ..sort((a, b) =>
              _coverageCategoryLabel(loc, a.eventCategory)
                  .compareTo(_coverageCategoryLabel(loc, b.eventCategory)));
        final countryOnly = coverage.isNotEmpty &&
            coverage.every((c) => c.isCountryOnly);

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  loc.coverageSheetTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (coverage.isEmpty)
                Text(
                  loc.coverageNoData,
                  style: const TextStyle(fontSize: 14),
                )
              else ...[
                if (countryOnly)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SemanticColors.alertSoft,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(PhosphorIconsRegular.info,
                            size: 18, color: SemanticColors.alertText),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            loc.coverageGlobalBaselineOnly,
                            style: const TextStyle(
                                fontSize: 13, color: SemanticColors.alertText),
                          ),
                        ),
                      ],
                    ),
                  ),
                ...coverage.map((c) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          _GradeChip(grade: c.grade),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _coverageCategoryLabel(
                                      loc, c.eventCategory),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                ),
                                Text(
                                  [
                                    if (c.freshnessDays != null)
                                      loc.coverageFreshness(c.freshnessDays!),
                                    loc.coverageSourceCount(c.sourceCount),
                                  ].join(' · '),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: BeeAwareTheme.textAux),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _openMenu(BuildContext context) {
    _clearHint();
    final rootContext = context; // 👈 importante para evitar erros

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) {
        final loc = AppLocalizations.of(sheetContext)!;
        final tokens = rootContext.read<TokenState>().tokens;
        final user = Supabase.instance.client.auth.currentUser;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ================= HEADER =================
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(rootContext);

                      if (user == null) {
                        Navigator.push(
                          rootContext,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      } else {
                        // FUTURO: profile
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        gradient: user == null
                            ? null
                            : const LinearGradient(
                                colors: [
                                  Color(0xFFFFF2CC),
                                  Color(0xFFFDE68A),
                                ],
                              ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Avatar
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  BeeAwareTheme.accent,
                                  const Color(0xFFFBBF24),
                                ],
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.transparent,
                              child: user == null
                                  ? const Icon(PhosphorIconsRegular.person,
                                      color: Colors.black)
                                  : const Icon(PhosphorIconsRegular.sealCheck,
                                      color: Colors.black),
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Text
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user == null
                                      ? loc.signInToBeeAware
                                      : (user.email ?? loc.signedIn),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                if (user == null || AppConfig.tokensEnabled)
                                  Text(
                                    user == null
                                        ? loc.secureLoginGoogleEmail
                                        : loc.tokensAvailable(tokens),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: BeeAwareTheme.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Arrow
                          const Icon(
                            PhosphorIconsRegular.caretRight,
                            size: 20,
                            color: BeeAwareTheme.textAux,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                const Divider(),

                _menuSectionLabel(loc.menuSectionAccount),

                // ================= BUY =================
                if (AppConfig.tokensEnabled)
                  _menuItem(
                    icon: PhosphorIconsRegular.creditCard,
                    label: loc.buyMoreCredits,
                    onTap: () {
                      Navigator.pop(rootContext);
                      Navigator.push(
                        rootContext,
                        MaterialPageRoute(
                          builder: (_) => const BuyTokensScreen(),
                        ),
                      );
                    },
                  ),

                // ================= ALERTS =================
                _menuItem(
                  icon: PhosphorIconsRegular.bellRinging,
                  label: loc.alertsMonitoring,
                  onTap: () {
                    Navigator.pop(rootContext);
                  },
                ),

                const Divider(height: 30),

                _menuSectionLabel(loc.menuSectionSupport),

                // ================= DATA =================
                _menuItem(
                  icon: PhosphorIconsRegular.chartBar,
                  label: loc.dataSources,
                  onTap: () {
                    Navigator.pop(rootContext);
                    _showOfficialLegendSheet(rootContext);
                  },
                ),

                _menuItem(
                  icon: PhosphorIconsRegular.globe,
                  label: loc.languageLabel,
                  onTap: () {
                    Navigator.pop(rootContext);
                    _showLanguagePicker(rootContext);
                  },
                ),

                _menuItem(
                  icon: PhosphorIconsRegular.shieldCheck,
                  label: loc.privacyLabel,
                  onTap: () async {
                    Navigator.pop(rootContext);

                    final uri =
                        Uri.parse('https://www.beeaware.io/privacy.html');

                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),

                _menuItem(
                  icon: PhosphorIconsRegular.info,
                  label: loc.aboutBeeAware,
                  onTap: () {
                    Navigator.pop(rootContext);
                    _showAboutSheet(rootContext);
                  },
                ),

                // ================= LOGOUT =================
                if (user != null) ...[
                  const Divider(height: 30),
                  _menuItem(
                    icon: PhosphorIconsRegular.signOut,
                    label: loc.signOut,
                    onTap: () async {
                      await Supabase.instance.client.auth.signOut();
                      Navigator.pop(rootContext);
                      setState(() {}); // ou atualize o state do menu
                      context.read<TokenState>().clear();
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _menuSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: BeeAwareTheme.textAux,
          ),
        ),
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
    );
  }

  void _showLanguagePicker(BuildContext rootContext) {
    final localeState = rootContext.read<LocaleState>();

    showDialog(
      context: rootContext,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext)!;

        Widget option(String label, Locale? value) {
          return RadioListTile<Locale?>(
            title: Text(label),
            value: value,
            groupValue: localeState.locale,
            onChanged: (selected) {
              localeState.setLocale(selected);
              Navigator.pop(dialogContext);
            },
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          title: Text(loc.languageLabel),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(loc.languageAutomatic, null),
              option(loc.languagePortuguese, const Locale('pt')),
              option(loc.languageEnglish, const Locale('en')),
            ],
          ),
        );
      },
    );
  }

  void _handleSearch(BuildContext context, String value) async {
    _clearHint();

    if (value.trim().isEmpty) return;

    final tokenState = context.read<TokenState>();

    // 🔥 bloqueia imediatamente
    if (AppConfig.tokensEnabled && !tokenState.hasTokens) {
      _showNoTokensDialog(context);
      return;
    }

    setState(() => _isSearching = true);

    final result = await _geocodeAddress(value);

    //print('GEOCODE RESULT: $result');

    if (result == null) {
      setState(() => _isSearching = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.addressNotFound)),
      );
      return;
    }

    if (AppConfig.tokensEnabled) {
      // 🔥 só consome token se encontrou endereço
      final success = await tokenState.useToken();

      if (!success) {
        _showNoTokensDialog(context);
        return;
      }

      final remaining = tokenState.tokens;

      if (remaining == 1) {
        setState(() => _showLowTokenWarning = true);

        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() => _showLowTokenWarning = false);
          }
        });
      }

      setState(() => _showZeroTokenBanner = remaining == 0);
    }

    setState(() {
      _searchLocation = result;
      _isSearching = false;
    });

    _mapController.move(result, 15);

    UkPoliceApi.refreshTrendBackground(
      lat: result.latitude,
      lng: result.longitude,
    );

    // sync oficial
    final bounds = _mapController.camera.visibleBounds;
    await IncidentStore.syncOfficialForBounds(bounds);

    _recentSearches.add(result);
    _detectBuyingIntent(context, result);
  }

  void _showNoTokensDialog(BuildContext rootContext) {
    showDialog(
      context: rootContext,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          title: Text(loc.noSearchTokensRemaining),
          content: Text(loc.unlockUnlimitedInsights),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(loc.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                // 🔥 fecha o dialog
                Navigator.pop(dialogContext);

                // 🔥 usa o context ORIGINAL da tela
                Navigator.pushNamed(rootContext, '/buyTokens');
              },
              child: Text(loc.buyMore),
            ),
          ],
        );
      },
    );
  }

  OverlayEntry? _trendOverlay;

  void _showSafetyTrend() async {
    UkPoliceApi.clearTrendCache();
    if (!mounted) return;

    final center = _searchLocation ??
        _mapController.camera.center ??
        _initialCenter ??
        _mapCenter;

    // 1) tenta cache
    List<MonthlyTrend>? policeTrend = UkPoliceApi.cachedTrend;

    // 2) fallback se cache vazio
    policeTrend ??= await UkPoliceApi.fetchTrend(
      lat: center.latitude,
      lng: center.longitude,
    );

    // 🔥 1. ordenar por mês
    policeTrend.sort((a, b) => a.month.compareTo(b.month));

// 🔥 2. descobrir último mês
    final last = policeTrend.last.month;

// 🔥 3. criar base correta de 12 meses
    final months = _getTrendMonths(last);

// 🔥 4. mapear dados da polícia corretamente
    final policeData = List<double>.filled(months.length, 0);

    final indexByYm = <String, int>{};
    for (int i = 0; i < months.length; i++) {
      final m = months[i];
      final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      indexByYm[key] = i;
    }

    for (final e in policeTrend) {
      final key = '${e.month.year}-${e.month.month.toString().padLeft(2, '0')}';

      final idx = indexByYm[key];
      if (idx != null) {
        policeData[idx] = e.count.toDouble();
      }
    }

    // comunidade alinhada aos mesmos meses da polícia
    final communityData = _buildTrendDataAligned(center, months);

    // soma final
    final data = List.generate(
      months.length,
      (i) => policeData[i] + communityData[i],
    );

    _openTrendOverlay(data, months);
  }

  void _loadTrendInBackground(LatLng center) {
    UkPoliceApi.refreshTrendBackground(
      lat: center.latitude,
      lng: center.longitude,
    );
  }

  void _openTrendOverlay(List<double> data, List<DateTime> months) {
    if (_trendOverlay != null) {
      _trendOverlay!.remove();
      _trendOverlay = null;
    }

    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final subtitle = months.isNotEmpty
        ? loc.trendSubtitleWithMonth(
            DateFormat.MMM(locale).format(months.last), months.last.year)
        : loc.trendSubtitleFallback;

    _trendOverlay = OverlayEntry(
      builder: (overlayContext) {
        return GestureDetector(
          onTap: () {
            _trendOverlay?.remove();
            _trendOverlay = null;
          },
          child: Material(
            color: Colors.black.withValues(alpha: 0.25),
            child: Center(
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: 360,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        loc.safetyTrendTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: BeeAwareTheme.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      SafetyTrendChart(values: data, months: months),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_trendOverlay!);
  }

  List<DateTime> _getTrendMonths(DateTime lastPoliceMonth) {
    return List.generate(
      12,
      (i) => DateTime(
        lastPoliceMonth.year,
        lastPoliceMonth.month - (11 - i),
        1,
      ),
    );
  }

  List<double> _buildTrendData(LatLng center, DateTime anchorMonth) {
    final anchor = DateTime(anchorMonth.year, anchorMonth.month, 1);
    final monthly = List<int>.filled(12, 0);

    for (final incident in _incidents) {
      final incidentMonth =
          DateTime(incident.dateTime.year, incident.dateTime.month, 1);

      final diffMonths = (anchor.year - incidentMonth.year) * 12 +
          (anchor.month - incidentMonth.month);

      if (diffMonths < 0 || diffMonths > 11) continue;

      final index = 11 - diffMonths;
      monthly[index]++;
    }

    return monthly.map((e) => e.toDouble()).toList();
  }

  List<double> _buildTrendDataAligned(LatLng center, List<DateTime> months) {
    final monthly = List<int>.filled(months.length, 0);

    // índice por mês (YYYY-MM)
    final indexByYm = <String, int>{};
    for (int i = 0; i < months.length; i++) {
      final m = months[i];
      final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
      indexByYm[key] = i;
    }

    for (final incident in _incidents) {
      // ✅ só comunidade
      if (incident.isOfficial) continue;

      final meters = _distanceCalc.as(
        LengthUnit.Meter,
        center,
        incident.location,
      );
      if (meters > 1609) continue;

      final dt = incident.dateTime;
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';

      final idx = indexByYm[key];
      if (idx == null) continue;

      monthly[idx]++;
    }

    return monthly.map((e) => e.toDouble()).toList();
  }

  List<double> _buildCommunityTrendForMonths(
      LatLng center, List<DateTime> months) {
    // índice rápido: yyyy-mm -> posição
    final index = <String, int>{};
    for (int i = 0; i < months.length; i++) {
      final dt = months[i];
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      index[key] = i;
    }

    final counts = List<int>.filled(months.length, 0);

    for (final incident in _incidents) {
      final key =
          '${incident.dateTime.year}-${incident.dateTime.month.toString().padLeft(2, '0')}';

      final pos = index[key];
      if (pos == null) continue;

      final meters = _distanceCalc.as(
        LengthUnit.Meter,
        center,
        incident.location,
      );

      if (meters > 1609) continue; // 1 mile

      counts[pos]++;
    }

    return counts.map((e) => e.toDouble()).toList();
  }

  List<double> _buildTrendFromHistorical(
      List<MapIncident> list, LatLng center) {
    final now = DateTime.now();

    // 🔥 últimos 12 meses
    final monthly = List<int>.filled(12, 0);

    for (final i in list) {
      // 🔥 normaliza o mês
      final incidentMonth = DateTime(i.dateTime.year, i.dateTime.month, 1);

      // 🔥 calcula diferença de meses (igual ao restante do app)
      final diffMonths = (now.year - incidentMonth.year) * 12 +
          (now.month - incidentMonth.month);

      // só últimos 12 meses
      if (diffMonths < 0 || diffMonths > 11) continue;

      // 🔥 filtro de distância
      final meters = _distanceCalc.as(
        LengthUnit.Meter,
        center,
        i.location,
      );

      if (meters > 1609) continue; // 1 mile

      // 🔥 índice cronológico (0 = mais antigo, 11 = mais recente)
      final index = 11 - diffMonths;

      monthly[index]++;
    }

    return monthly.map((e) => e.toDouble()).toList();
  }

  Future<LatLng?> _geocodeAddress(String query) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1&countrycodes=gb',
      );

      final response = await http.get(url, headers: {
        'Accept': 'application/json',
      });

      if (response.statusCode != 200) return null;

      final decoded = json.decode(response.body);

      if (decoded.isEmpty) return null;

      final lat = double.tryParse(decoded[0]['lat']);
      final lon = double.tryParse(decoded[0]['lon']);

      if (lat == null || lon == null) return null;

      return LatLng(lat, lon);
    } catch (e) {
      debugPrint('Geocode error: $e');
      return null;
    }
  }

  Map<IncidentSeverity, int> _summaryWithin1Mile(LatLng center) {
    const radiusMeters = 1609.34; // 1 mile

    int low = 0;
    int medium = 0;
    int high = 0;

    // Usa a lista já filtrada por time/severity/distance? NÃO.
    // Aqui a gente quer o volume REAL ao redor do endereço buscado,
    // então usamos _incidents (todos carregados) e contamos por severidade.
    for (final i in _incidents) {
      final meters = _distanceCalc.as(
        LengthUnit.Meter,
        center,
        i.location,
      );

      if (meters <= radiusMeters) {
        if (i.severity == IncidentSeverity.high)
          high++;
        else if (i.severity == IncidentSeverity.medium)
          medium++;
        else
          low++;
      }
    }

    return {
      IncidentSeverity.low: low,
      IncidentSeverity.medium: medium,
      IncidentSeverity.high: high,
    };
  }

  void _showSearchSummaryPopup(
    BuildContext context,
    Map<IncidentSeverity, int> summary,
  ) {
    final low = summary[IncidentSeverity.low] ?? 0;
    final med = summary[IncidentSeverity.medium] ?? 0;
    final high = summary[IncidentSeverity.high] ?? 0;

    showDialog(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext)!;
        return Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  loc.incidentsWithin1Mile,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                _severityRow(
                    SeverityColors.label(dialogContext, IncidentSeverity.high),
                    high,
                    SeverityColors.high),
                _severityRow(
                    SeverityColors.label(
                        dialogContext, IncidentSeverity.medium),
                    med,
                    SeverityColors.medium),
                _severityRow(
                    SeverityColors.label(dialogContext, IncidentSeverity.low),
                    low,
                    SeverityColors.low),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(loc.close),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _detectBuyingIntent(BuildContext context, LatLng location) {
    const radiusMeters = 1200; // ~1 mile

    int nearbySearches = 0;

    for (final s in _recentSearches) {
      final meters = _distanceCalc.as(
        LengthUnit.Meter,
        location,
        s,
      );

      if (meters <= radiusMeters) {
        nearbySearches++;
      }
    }

    // Threshold: 3 buscas na mesma área
    if (nearbySearches >= 3) {
      _showAlertOffer(context);
    }
  }

  void _showAlertOffer(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final loc = AppLocalizations.of(dialogContext)!;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsRegular.bellRinging,
                    size: 36, color: BeeAwareTheme.accent),
                const SizedBox(height: 12),
                Text(
                  loc.stayUpdatedInArea,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  loc.alertOfferBody,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    // futuramente: ativar assinatura
                  },
                  child: Text(loc.yesNotifyMe),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(loc.notNow),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _severityRow(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            value.toString(),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// BeeAware Global blueprint §6.2 source grades, collapsed onto this
// schema's actual output (see location_coverage_rpc.sql) — A+/A read as
// strong local/official data, B a regional baseline, C the coarse global
// (UNODC) fallback. D/U aren't produced by any adapter yet.
Color _gradeColor(String grade) {
  switch (grade) {
    case 'A+':
    case 'A':
      return const Color(0xFF16A34A);
    case 'B':
      return const Color(0xFFCA8A04);
    case 'C':
      return const Color(0xFF9333EA);
    case 'D':
      return const Color(0xFFDC2626);
    default:
      return BeeAwareTheme.textSecondary;
  }
}

class _GradeChip extends StatelessWidget {
  final String grade;

  const _GradeChip({required this.grade});

  @override
  Widget build(BuildContext context) {
    final color = _gradeColor(grade);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        grade,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// Ícone compacto padrão da barra inferior — Tooltip cobre tanto hover
// (desktop) quanto toque longo (mobile), o que o _hover manual de cada
// botão anterior não fazia: em celular o rótulo nunca aparecia. Tamanho
// reduzido (~36px) de propósito — a barra passou a acomodar até 5 ícones
// de cada lado do botão central, não cabe no alvo de toque padrão do
// Material (48px).
class _BarIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _BarIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: BeeAwareTheme.primary,
        iconSize: 20,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
        onPressed: onTap,
      ),
    );
  }
}

// Nota de cobertura (grade A+ a D) — mantém o círculo colorido com a
// letra, que é informação, não decoração; só o rótulo em hover/toque-
// longo virou Tooltip, como todo outro ícone da barra.
class _CoverageBadge extends StatelessWidget {
  final String grade;
  final VoidCallback onTap;

  const _CoverageBadge({required this.grade, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _gradeColor(grade);
    return Tooltip(
      message: AppLocalizations.of(context)!.coverageBadgeTooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              grade,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ),
      ),
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
                    color: widget.color == SeverityColors.low
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
  final VoidCallback onTrend;
  final VoidCallback onCoverageTap;
  final String? coverageGrade;

  const _BottomBar({
    required this.onReport,
    required this.onPolice,
    required this.onFilters,
    required this.onTrend,
    required this.onCoverageTap,
    this.coverageGrade,
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
    final loc = AppLocalizations.of(context)!;
    return SizedBox(
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Esquerda: ações sobre a visão atual do mapa.
                Row(
                  children: [
                    _BarIcon(
                      icon: PhosphorIconsRegular.siren,
                      tooltip: loc.emergencyServices,
                      onTap: widget.onPolice,
                    ),
                    _BarIcon(
                      icon: PhosphorIconsRegular.funnel,
                      tooltip: loc.filters,
                      onTap: widget.onFilters,
                    ),
                  ],
                ),
                // Direita: informação sobre a área + ações de sistema.
                Row(
                  children: [
                    _BarIcon(
                      icon: PhosphorIconsRegular.chartLine,
                      tooltip: loc.safetyTrendShort,
                      onTap: widget.onTrend,
                    ),
                    if (widget.coverageGrade != null)
                      _CoverageBadge(
                        grade: widget.coverageGrade!,
                        onTap: widget.onCoverageTap,
                      ),
                    if (canInstall)
                      _BarIcon(
                        icon: PhosphorIconsRegular.downloadSimple,
                        tooltip: loc.installAppTooltip,
                        onTap: () {
                          if (js.context.callMethod('isPwaInstallable') ==
                              true) {
                            js.context.callMethod('triggerPwaInstall');
                          } else {
                            pwa.PWAInstall().promptInstall_();
                          }
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            child: Tooltip(
              message: loc.shareReportTooltip,
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

class _AnimatedCentralButtonState extends State<_AnimatedCentralButton>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;

  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  )..repeat(reverse: true);

  void _setScale(double value) {
    if (!mounted) return;
    setState(() => _scale = value);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

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
          child: AnimatedBuilder(
            animation: _glowController,
            builder: (context, child) {
              final glow = reduceMotion ? 0.0 : _glowController.value;
              return Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    // Subtle amber pulse — the one spot in the app where
                    // the accent color calls attention to itself.
                    BoxShadow(
                      color:
                          BeeAwareTheme.accent.withValues(alpha: 0.35 * (1 - glow)),
                      blurRadius: 6,
                      spreadRadius: 8 * glow,
                    ),
                    BoxShadow(
                      color: BeeAwareTheme.primary.withValues(alpha: 0.10),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(5),
                child: child,
              );
            },
            child: SvgPicture.asset(
              'assets/logo/beeaware_symbol.svg',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
