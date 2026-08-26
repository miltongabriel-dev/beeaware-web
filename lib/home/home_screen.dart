import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, KeyDownEvent;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:aware/config/rounded_hexagon_painter.dart';
import 'package:aware/config/emergency_numbers.dart';

import '../map/map_incident.dart';
import '../map/incident_store.dart';
import '../map/bee_incident_pin.dart';
import '../config/app_config.dart';
import '../theme/beeaware_theme.dart';
import '../theme/bee_loader.dart';
import '../theme/emergency_sos.dart';
import '../report/report_icons.dart';
import '../report/report_labels.dart';
import '../l10n/app_localizations.dart';
import '../state/locale_state.dart';
import '../theme/fade_in.dart';
import '../utils/relative_time.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:aware/auth/login_screen.dart';

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
import '../area/area_intelligence_screen.dart';
import '../backend/route_awareness_api.dart';
import '../utils/geocoding.dart';
import '../utils/preferred_country_code.dart';

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

  // Route Awareness (roadmap 9.5/11.12) — integrated directly into the
  // main search bar rather than a separate screen: swaps the single
  // search field into a compact From/To pair over the same map, so both
  // candidate routes draw on the map the user is already looking at
  // instead of a second, disconnected view. See _RouteSearchBar/
  // _RouteResultsCard below.
  bool _routeMode = false;
  final _routeFromController = TextEditingController();
  final _routeToController = TextEditingController();
  LatLng? _routeFromPoint;
  LatLng? _routeToPoint;
  List<AddressSuggestion> _routeFromSuggestions = [];
  List<AddressSuggestion> _routeToSuggestions = [];
  Timer? _routeFromDebounce;
  Timer? _routeToDebounce;
  List<RouteOption> _routeOptions = [];
  int _selectedRouteIndex = 0;
  bool _routeLoading = false;
  String? _routeError;
  static const List<Color> _routeColors = [
    BeeAwareTheme.primary,
    Color(0xFF3B82F6),
  ];

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

  // Mesmas 6 categorias fixas de ReportCategoryScreen — repetidas aqui
  // porque a lista de lá é privada e o valor gravado em MapIncident.category
  // já é sempre uma dessas strings (ou 'Other').
  static const List<String> _allCategories = [
    'Harassment',
    'Suspicious activity',
    'Theft',
    'Violence',
    'Drugs',
    'Other',
  ];

  final Set<String> _activeCategories = _allCategories.toSet();

  final MapController _mapController = MapController();

  OverlayEntry? _hintOverlay;

  // 📍 Função que tira de Epsom e vai para sua rua
  //
  // Previously swallowed every outcome silently (bare `catch (_) {}`, no
  // branch at all for a denied/unavailable permission) — a user tapping
  // this button while location access was blocked saw literally nothing
  // happen, with no way to tell "permission denied" apart from "just
  // slow" or "broken". Now surfaces a SnackBar for both cases, same
  // pattern _handleSearchSubmitted already uses for addressNotFound.
  // Once a browser origin has permanently denied geolocation, the Web
  // Geolocation API won't show its native prompt again on
  // requestPermission() — the browser only lets the user re-grant it
  // from its own site-settings UI — so deniedForever's message says that
  // explicitly instead of implying a retry will help.
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
          timeLimit: const Duration(seconds: 10),
        );

        _mapController.move(
          LatLng(position.latitude, position.longitude),
          15.0,
        );
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            permission == LocationPermission.deniedForever
                ? AppLocalizations.of(context)!.locationPermissionBlocked
                : AppLocalizations.of(context)!.locationPermissionDenied,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.locationPermissionError),
        ),
      );
    }
  }

  // ================= ROTA (roadmap 9.5/11.12) =================
  //
  // Enters/exits the main search bar's From/To mode. Pre-fills From with
  // the user's current location when already known (_userCurrentLocation
  // is populated by _loadUserLocation on app start) — same default the
  // wireframe assumes ("From: My location") — without forcing a fresh
  // permission prompt just to open the panel; the crosshair button in
  // _RouteSearchBar covers the case where it isn't known yet or the user
  // wants to refresh it.
  void _enterRouteMode() {
    _closeMenu();
    setState(() {
      _routeMode = true;
      _suggestions = [];
      if (_filterOverlay != null) {
        _filterOverlay!.remove();
        _filterOverlay = null;
      }
      if (_userCurrentLocation != null) {
        _routeFromPoint = _userCurrentLocation;
        _routeFromController.text = AppLocalizations.of(context)!.myLocation;
      }
    });
  }

  void _exitRouteMode() {
    setState(() {
      _routeMode = false;
      _routeFromController.clear();
      _routeToController.clear();
      _routeFromPoint = null;
      _routeToPoint = null;
      _routeFromSuggestions = [];
      _routeToSuggestions = [];
      _routeOptions = [];
      _selectedRouteIndex = 0;
      _routeError = null;
    });
  }

  void _selectRoute(int index) {
    setState(() => _selectedRouteIndex = index);
  }

  void _onRouteFromChanged(String value) {
    _routeFromPoint = null;
    _routeFromDebounce?.cancel();
    _routeFromDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await fetchAddressSuggestions(value);
      if (!mounted) return;
      setState(() => _routeFromSuggestions = results);
    });
  }

  void _onRouteToChanged(String value) {
    _routeToPoint = null;
    _routeToDebounce?.cancel();
    _routeToDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await fetchAddressSuggestions(value);
      if (!mounted) return;
      setState(() => _routeToSuggestions = results);
    });
  }

  void _selectRouteFromSuggestion(AddressSuggestion s) {
    _routeFromController.text = s.full;
    setState(() {
      _routeFromPoint = s.point;
      _routeFromSuggestions = [];
    });
  }

  void _selectRouteToSuggestion(AddressSuggestion s) {
    _routeToController.text = s.full;
    setState(() {
      _routeToPoint = s.point;
      _routeToSuggestions = [];
    });
  }

  // Same permission-outcome handling as _centerMapOnUser (see its own
  // header) — a separate method rather than reusing that one directly
  // since this sets the route From field/point instead of moving the
  // map.
  Future<void> _useMyLocationForRoute() async {
    final loc = AppLocalizations.of(context)!;
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              permission == LocationPermission.deniedForever
                  ? loc.locationPermissionBlocked
                  : loc.locationPermissionDenied,
            ),
          ),
        );
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (!mounted) return;
      setState(() {
        _routeFromPoint = LatLng(position.latitude, position.longitude);
        _routeFromController.text = loc.myLocation;
        _routeFromSuggestions = [];
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.locationPermissionError)),
      );
    }
  }

  Future<void> _searchRoutes() async {
    final loc = AppLocalizations.of(context)!;
    setState(() {
      _routeLoading = true;
      _routeError = null;
      _routeOptions = [];
      _routeFromSuggestions = [];
      _routeToSuggestions = [];
    });

    final from =
        _routeFromPoint ?? await geocodeAddress(_routeFromController.text);
    final to = _routeToPoint ?? await geocodeAddress(_routeToController.text);

    if (from == null || to == null) {
      if (!mounted) return;
      setState(() {
        _routeLoading = false;
        _routeError = loc.addressNotFound;
      });
      return;
    }

    try {
      final routes =
          await RouteAwarenessApi.fetchRoutes(origin: from, destination: to);

      if (!mounted) return;

      if (routes.isEmpty) {
        setState(() {
          _routeLoading = false;
          _routeError = loc.routeAwarenessNoRoutes;
        });
        return;
      }

      setState(() {
        _routeFromPoint = from;
        _routeToPoint = to;
        _routeOptions = routes;
        _selectedRouteIndex = 0;
        _routeLoading = false;
      });

      final bounds =
          LatLngBounds.fromPoints(routes.expand((r) => r.points).toList());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(64)),
        );
      });
    } catch (e) {
      debugPrint('Route Awareness fetchRoutes failed: $e');
      if (!mounted) return;
      setState(() {
        _routeLoading = false;
        _routeError = loc.routeAwarenessNoRoutes;
      });
    }
  }

  // BeeAware itself has no turn-by-turn navigation (roadmap 11.12's
  // Route Awareness is explicitly a comparison/awareness layer, not a
  // navigator) — this hands off to the app the user already navigates
  // with, honouring whichever route they picked in _RouteResultsCard
  // (not always Route A). Waze's URL scheme (waze.com/ul) only accepts a
  // destination, no custom origin or via-point — it always navigates
  // from wherever the device currently is, so the selected route can't
  // actually steer it; _routeFromPoint is unused for that branch on
  // purpose, not an oversight. Google Maps' directions URL does support
  // a `waypoints` param, so when the selected route isn't just the
  // straight A-to-B line, a point roughly midway along its own geometry
  // is passed as a soft hint to bias Google's own routing toward a
  // similar path — not exact fidelity (Google still computes its own
  // route), but closer to the path the user actually reviewed than
  // giving it only origin/destination would be.
  Future<void> _openInExternalMaps(String app) async {
    final from = _routeFromPoint;
    final to = _routeToPoint;
    if (from == null || to == null) return;

    final selected = _selectedRouteIndex < _routeOptions.length
        ? _routeOptions[_selectedRouteIndex]
        : null;
    final waypoint = (selected != null && selected.points.length > 2)
        ? selected.points[selected.points.length ~/ 2]
        : null;

    final Uri uri;
    switch (app) {
      case 'waze':
        uri = Uri.parse(
            'https://waze.com/ul?ll=${to.latitude},${to.longitude}&navigate=yes');
        break;
      case 'apple':
        uri = Uri.parse(
            'https://maps.apple.com/?saddr=${from.latitude},${from.longitude}'
            '&daddr=${to.latitude},${to.longitude}&dirflg=w');
        break;
      case 'google':
      default:
        final waypointsParam = waypoint != null
            ? '&waypoints=${waypoint.latitude},${waypoint.longitude}'
            : '';
        uri = Uri.parse('https://www.google.com/maps/dir/?api=1'
            '&origin=${from.latitude},${from.longitude}'
            '&destination=${to.latitude},${to.longitude}'
            '$waypointsParam&travelmode=walking');
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // Replaces the pill-shaped search bar in place when _routeMode is on —
  // same top-left-right Positioned slot, just a taller card, so the map
  // and the route it draws stay the single view the whole time (roadmap
  // 9.5 as a panel over the map, not RouteAwarenessScreen's earlier
  // separate full-screen form). Own inline suggestion dropdowns per
  // field (_RouteFieldSuggestions below) rather than a shared overlay —
  // simplest way to keep two independent lists (From/To) from fighting
  // over one Positioned slot.
  Widget _buildRouteSearchBar() {
    final loc = AppLocalizations.of(context)!;

    // The panel sits in a Positioned(top: 60, ...) with no bottom bound,
    // inside a Stack — a Stack never scrolls, so content taller than the
    // remaining screen space was previously just unreachable: the To
    // suggestions dropdown (up to 180px) plus both fields could push the
    // search button below the visible area entirely, with no way to
    // reach it (confirmed by the report: "buscar" cut off, To
    // suggestions not tappable — both are the same root cause, not two
    // separate bugs). Capping the panel's height and making it scroll
    // internally means the button and every suggestion stay reachable
    // regardless of how much content is open above them.
    //
    // MediaQuery.size stays the full device height even once the on-screen
    // keyboard opens (Scaffold's resizeToAvoidBottomInset shrinks the body,
    // not .size), so subtracting viewInsets.bottom was the fix for a
    // browser tab. It isn't enough for an iOS home-screen-installed PWA
    // specifically (this app, per the report's screenshot — no browser
    // chrome): standalone PWAs on iOS have a long-standing WebKit bug
    // where opening the keyboard changes neither size.height nor
    // viewInsets.bottom at all, so there is no reliable signal here to
    // detect it by. A hard cap well clear of where any phone's keyboard
    // starts, independent of that unreliable computed height, is what
    // actually keeps the button above the keyboard rather than behind it
    // (still cortando after the viewInsets-only fix).
    // Whether either field currently has an open dropdown — while one
    // does, the button is hidden below (see its own comment): searching
    // routes mid-selection isn't a real action anyway, and it lets the
    // card grow enough to show suggestions without needing the button to
    // still fit in whatever's left, which is what the previous fixed cap
    // (300) was clipping the button itself against once 3+ suggestions
    // were open.
    final hasOpenSuggestions =
        _routeFromSuggestions.isNotEmpty || _routeToSuggestions.isNotEmpty;

    final mq = MediaQuery.of(context);
    final availableHeight = mq.size.height - 60 - 24 - mq.viewInsets.bottom;
    final hardCap = hasOpenSuggestions ? 460.0 : 220.0;
    final maxHeight = availableHeight < hardCap
        ? (availableHeight > 200 ? availableHeight : 200.0)
        : hardCap;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight > 200 ? maxHeight : 200),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ponto + linha ligando origem e destino, mesmo padrão visual
              // de Google Maps/Uber — o ícone já diz "de"/"para", então o
              // campo não precisa de um labelText próprio. labelText + border:
              // InputBorder.none era a causa real da distorção: um rótulo
              // flutuante do Material precisa de uma borda pra "pousar" nela,
              // e sem isso ele fica espremido em cima do texto digitado.
              // Suggestions are deliberately NOT nested inside this
              // IntrinsicHeight (they used to be, right under each field) —
              // IntrinsicHeight pre-measures its subtree's height, and a
              // scrollable Viewport (the ListView inside
              // _RouteFieldSuggestions) doesn't report a real intrinsic
              // height back, so the card sized itself as if the list
              // wasn't there while the list still painted past that
              // boundary — suggestions rendered as bare text straight on
              // top of the map, with no white card behind them (reported
              // as "autopreenchimento overflow para fora, completamente
              // errado"). Keeping only the two fixed-height field rows
              // under IntrinsicHeight (which is all the dot/line/flag
              // rail actually needs to stretch against) and rendering the
              // suggestion lists as ordinary siblings after it keeps them
              // inside the same scrollable card without that interaction.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Container(
                            width: 1,
                            color: BeeAwareTheme.border,
                          ),
                        ),
                        Icon(PhosphorIconsRegular.flagCheckered,
                            size: 14, color: BeeAwareTheme.textSecondary),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _routeFromController,
                                  onChanged: _onRouteFromChanged,
                                  decoration: InputDecoration(
                                    hintText: loc.routeAwarenessFromHint,
                                    isDense: true,
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: loc.routeAwarenessUseMyLocation,
                                icon: const Icon(PhosphorIconsRegular.crosshair,
                                    color: Colors.blue, size: 20),
                                onPressed: _useMyLocationForRoute,
                              ),
                            ],
                          ),
                          const Divider(height: 1),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _routeToController,
                                  onChanged: _onRouteToChanged,
                                  decoration: InputDecoration(
                                    hintText: loc.routeAwarenessToHint,
                                    isDense: true,
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: loc.close,
                                icon: const Icon(PhosphorIconsRegular.x,
                                    color: BeeAwareTheme.textSecondary,
                                    size: 20),
                                onPressed: _exitRouteMode,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Indented by 22 (10 dot width + 12 spacing) to line up under
              // the field text above rather than the dot/flag rail.
              if (_routeFromSuggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: _RouteFieldSuggestions(
                    suggestions: _routeFromSuggestions,
                    onSelected: _selectRouteFromSuggestion,
                  ),
                ),
              if (_routeToSuggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: _RouteFieldSuggestions(
                    suggestions: _routeToSuggestions,
                    onSelected: _selectRouteToSuggestion,
                  ),
                ),
              // Hidden while a dropdown is open — picking a suggestion is
              // the only thing to do at that point, and keeping the
              // button out of the layout means its visibility never
              // depends on how many suggestions happen to be showing.
              if (!hasOpenSuggestions) ...[
                const SizedBox(height: 10),
                // No explicit height: the theme's ElevatedButton style
                // (see beeaware_theme.dart) applies 16px of padding above
                // and below the label on top of the label's own line
                // height — a forced height: 40 box (the previous code
                // here) is a good deal shorter than that combined natural
                // height, so the label rendered vertically sliced inside
                // it. Purely cosmetic (the button still filled its area
                // and was still tappable), but let it size itself instead
                // of fighting the theme, the same way every other
                // ElevatedButton in the app already does.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _routeLoading ? null : _searchRoutes,
                    child: _routeLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(loc.routeAwarenessSearchButton),
                  ),
                ),
                if (_routeError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _routeError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, color: BeeAwareTheme.textSecondary),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
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
        countryCode: preferredCountryCode(_userCurrentLocation).toUpperCase(),
      );

      if (mounted) setState(() => _coverage = coverage);
    });
  }

  // Tapping a colored municipality on MunicipalityChoroplethLayer opens
  // Area Intelligence (roadmap wireframe 9.2) for it. No hit-testing API
  // on the polygon layer itself is used here (flutter_map 7's
  // PolygonLayer.hitNotifier would need wrapping the map in its own
  // GestureDetector, on top of the one MapOptions.onTap already covers) —
  // instead this reuses the tapped LatLng MapOptions.onTap already
  // provides and does a plain point-in-polygon test against the same
  // _crimeSummary list the choropleth itself renders, so "which
  // municipality did they tap" can never disagree with what's on screen.
  void _openAreaIntelligenceIfTapped(LatLng point) {
    for (final summary in _crimeSummary) {
      for (final ring in summary.polygons) {
        if (_pointInPolygon(point, ring)) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AreaIntelligenceScreen(
                cityIbgeCode: summary.cityIbgeCode,
                cityName: summary.cityName,
                stateCode: summary.stateCode,
                tapLat: point.latitude,
                tapLng: point.longitude,
              ),
            ),
          );
          return;
        }
      }
    }
  }

  // Standard ray-casting point-in-polygon test (even-odd rule) — the
  // municipality boundaries here are simple rings (holes already dropped
  // by BrazilCrimeSummaryApi._parsePolygons, see its own doc comment),
  // so this doesn't need to handle holes either.
  static bool _pointInPolygon(LatLng point, List<LatLng> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final xi = ring[i].longitude, yi = ring[i].latitude;
      final xj = ring[j].longitude, yj = ring[j].latitude;
      final intersects = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _clearHint();
    _subscription?.cancel();
    _syncTimer?.cancel();
    _boundsDebounce?.cancel();
    _routeFromController.dispose();
    _routeToController.dispose();
    _routeFromDebounce?.cancel();
    _routeToDebounce?.cancel();

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

      // Category filter is a community-report concept (the 6 fixed report
      // categories) — official police records use their own category
      // string ('Police report') and must stay visible regardless of
      // which category chips are selected.
      if (!i.isOfficial && !_activeCategories.contains(i.category)) {
        return false;
      }

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
              // Só uma superfície flutuante aberta por vez: tocar no mapa
              // fecha as sugestões de busca, como tocar fora fecharia
              // qualquer outro painel.
              onTap: (_, point) {
                if (_suggestions.isNotEmpty) {
                  setState(() => _suggestions = []);
                }
                _openAreaIntelligenceIfTapped(point);
              },
              onMapReady: () {
                _loadUserLocation(); // keep (helps web/PWA)
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
              // Carto's free/keyless "light_all" tiles (used here since
              // this screen's design was built around it) stopped working
              // without an API key — every request now returns their
              // "API KEY REQUIRED" watermark tile instead of a real map,
              // confirmed live, not a local/testing artifact. Standard
              // OpenStreetMap tiles are the immediate fix: still genuinely
              // free/keyless, but busier/more colourful than the light
              // style this was designed against — a stopgap, not a
              // redesign; getting a real (free) Carto key would restore
              // the original look, but that needs the account holder's
              // own email submitted to Carto's own signup form, not
              // something to do on their behalf.
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'io.beeaware.app',
                tileProvider: CancellableNetworkTileProvider(),
              ),
              RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [
                  TextSourceAttribution(
                    '© OpenStreetMap contributors',
                    onTap: () =>
                        launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
                  ),
                ],
              ),

              // Violência/crime por município (Brasil) — abaixo dos pins,
              // acima do mapa base.
              MunicipalityChoroplethLayer(summaries: _crimeSummary),

              // Route Awareness — desenha direto no mapa principal em vez
              // de uma tela separada, para as rotas nunca perderem
              // contexto do que já está visível.
              if (_routeOptions.isNotEmpty) ...[
                // A rota selecionada desenha por cima (mais grossa, cor
                // cheia); as outras ficam finas e translúcidas — o
                // usuário escolhe qual seguir tocando no card de
                // resultado (_RouteResultsCard), e o mapa reflete isso.
                PolylineLayer(
                  polylines: [
                    for (var i = 0; i < _routeOptions.length; i++)
                      if (i != _selectedRouteIndex)
                        Polyline(
                          points: _routeOptions[i].points,
                          strokeWidth: 4,
                          color: _routeColors[i % _routeColors.length]
                              .withValues(alpha: 0.35),
                        ),
                    if (_selectedRouteIndex < _routeOptions.length)
                      Polyline(
                        points: _routeOptions[_selectedRouteIndex].points,
                        strokeWidth: 6,
                        color: _routeColors[
                            _selectedRouteIndex % _routeColors.length],
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (_routeFromPoint != null)
                      Marker(
                        point: _routeFromPoint!,
                        width: 26,
                        height: 26,
                        child: const Icon(PhosphorIconsRegular.mapPinLine,
                            color: Colors.blue, size: 26),
                      ),
                    if (_routeToPoint != null)
                      Marker(
                        point: _routeToPoint!,
                        width: 26,
                        height: 26,
                        child: const Icon(PhosphorIconsRegular.flagCheckered,
                            color: BeeAwareTheme.textPrimary, size: 26),
                      ),
                  ],
                ),
              ],

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
                                fontSize: 11,
                                color: BeeAwareTheme.textSecondary),
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
                                  fontSize: 11,
                                  color: BeeAwareTheme.textSecondary),
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

                  if (_routeMode) return _buildRouteSearchBar();

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
                          child: Focus(
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent &&
                                  event.logicalKey ==
                                      LogicalKeyboardKey.escape) {
                                setState(() => _suggestions = []);
                                FocusScope.of(context).unfocus();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
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
                                // Só uma superfície flutuante por vez: abrir
                                // sugestões fecha o painel de filtros e o
                                // menu.
                                if (_filterOverlay != null) {
                                  _filterOverlay!.remove();
                                  _filterOverlay = null;
                                }
                                _closeMenu();
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
                        ),

                        // Tokens badge
                        if (AppConfig.tokensEnabled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  BeeAwareTheme.accent.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
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
                      final String display = item['display_name'] ?? '';
                      final parts = display.split(',');
                      final primary = parts.first.trim();
                      final secondary = parts.length > 1
                          ? parts.sublist(1).join(',').trim()
                          : '';

                      return ListTile(
                        leading: const Icon(PhosphorIconsRegular.mapPin),
                        title: Text(
                          primary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: secondary.isEmpty
                            ? null
                            : Text(
                                secondary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: BeeAwareTheme.textSecondary,
                                ),
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

          // Chips de filtro ativo sobre o mapa — só aparecem quando algum
          // filtro aplicado difere do padrão, e só quando as sugestões de
          // busca não estão ocupando o mesmo espaço.
          if (_suggestions.isEmpty && _hasActiveFilters)
            Positioned(
              top: 120,
              left: 20,
              right: 20,
              child: _buildActiveFilterChips(context),
            ),

          // Controle de zoom, botão "centralizar no usuário" e o FAB de
          // rota vivem todos na borda direita — o mesmo espaço horizontal
          // onde o painel de rota (From/To) é desenhado quando _routeMode
          // está ativo. O zoom control em especial ocupa a borda inteira
          // (top: 0, bottom: 0), então com o painel aberto ele — e os dois
          // FABs — ficavam desenhados por cima do botão "Buscar rotas" e
          // da lista de sugestões, cortando-os visualmente (relatado como
          // "botão buscar cortado" / "autopreenchimento overflow"). Nenhum
          // dos três é útil com o painel aberto (ele já tem seu próprio
          // "usar minha localização" por campo, e refazer uma rota não faz
          // sentido dentro do próprio modo de rota), então somem enquanto
          // _routeMode for true.
          if (!_routeMode) ...[
            // Controle de zoom — meio-transparente, centralizado
            // verticalmente na borda direita, entre a busca e a bússola.
            Positioned(
              top: 0,
              bottom: 0,
              right: 16,
              child: Align(
                alignment: Alignment.centerRight,
                child: _ZoomControl(mapController: _mapController),
              ),
            ),

            // 📍 BOTÃO CENTRALIZAR NO USUÁRIO (bússola) — bottoms aqui não
            // precisam mais compensar a altura de uma bottom bar própria
            // desta tela: a navegação global agora vive em
            // RootScreen.bottomNavigationBar, fora do Stack deste widget, e
            // o Scaffold já exclui essa área do espaço disponível pro body.
            Positioned(
              right: 16,
              bottom: 16,
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

            // 🧭 ROTA — botão flutuante próprio na borda direita (padrão
            // Google Maps/Waze de empilhar ações do mapa nessa borda).
            Positioned(
              right: 16,
              bottom: 76,
              child: FloatingActionButton(
                mini: true,
                heroTag: 'route-fab',
                backgroundColor: BeeAwareTheme.primary,
                tooltip: AppLocalizations.of(context)!.routeAwarenessMenuLabel,
                onPressed: _enterRouteMode,
                child: const Icon(
                  PhosphorIconsRegular.signpost,
                  color: Colors.white,
                ),
              ),
            ),

            // 🔽 FILTROS — antes vivia dentro da bottom bar só do mapa;
            // agora que essa barra virou a navegação global do app
            // (Início/Mapa/Alertas/Perfil), filtro e tendência viram
            // botões flutuantes próprios, empilhados com os outros
            // controles do mapa na borda direita.
            Positioned(
              right: 16,
              bottom: 136,
              child: FloatingActionButton(
                mini: true,
                heroTag: 'filters-fab',
                backgroundColor: Colors.white,
                tooltip: AppLocalizations.of(context)!.filters,
                onPressed: _showFiltersOverlay,
                child: const Icon(
                  PhosphorIconsRegular.funnel,
                  color: BeeAwareTheme.primary,
                ),
              ),
            ),

            // 📈 TENDÊNCIA DE SEGURANÇA — mesma lógica do item acima.
            Positioned(
              right: 16,
              bottom: 196,
              child: FloatingActionButton(
                mini: true,
                heroTag: 'trend-fab',
                backgroundColor: Colors.white,
                tooltip: AppLocalizations.of(context)!.safetyTrendShort,
                onPressed: _showSafetyTrend,
                child: const Icon(
                  PhosphorIconsRegular.chartLine,
                  color: BeeAwareTheme.primary,
                ),
              ),
            ),
          ],

          // 🚨 SOS — canto superior direito, espelhando o logo no canto
          // superior esquerdo. Vermelho e com texto (nunca só ícone),
          // sempre visível independente do estado da busca/rota, mesmo
          // padrão de botão de emergência flutuante e inconfundível que
          // apps de segurança usam.
          Positioned(
            top: 16,
            right: 16,
            child: FadeInUp(
              child: SosButton(
                label: AppLocalizations.of(context)!.sosBarLabel(
                    emergencyNumbersFor(preferredCountryCode(_userCurrentLocation))
                        .primary),
                onTap: () => showEmergencySheet(
                    context, preferredCountryCode(_userCurrentLocation)),
              ),
            ),
          ),

          // Route Awareness — comparação das rotas encontradas, acima da
          // bottom bar, só quando há resultado (roadmap 9.5's route list,
          // integrada ao mapa em vez de uma tela própria).
          if (_routeOptions.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 100,
              child: _RouteResultsCard(
                routes: _routeOptions,
                colors: _routeColors,
                selectedIndex: _selectedRouteIndex,
                onSelect: _selectRoute,
                onOpenInApp: _openInExternalMaps,
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
                  style: const TextStyle(
                      fontSize: 14, color: BeeAwareTheme.textSecondary)),
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
              _buildLegendItem(
                  SeverityColors.high,
                  SeverityColors.labelSuffixed(
                      sheetContext, IncidentSeverity.high)),
              const SizedBox(height: 6),
              _buildLegendItem(
                  SeverityColors.medium,
                  SeverityColors.labelSuffixed(
                      sheetContext, IncidentSeverity.medium)),
              const SizedBox(height: 6),
              _buildLegendItem(
                  SeverityColors.low,
                  SeverityColors.labelSuffixed(
                      sheetContext, IncidentSeverity.low)),
              const SizedBox(height: 16),
              Text(
                loc.choroplethNoDataDisclaimer,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: BeeAwareTheme.textSecondary),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  OverlayEntry? _filterOverlay;
  OverlayEntry? _menuOverlay;

  void _closeMenu() {
    _menuOverlay?.remove();
    _menuOverlay = null;
  }

  void _showFiltersOverlay() {
    if (!mounted) return;

    // Só uma superfície flutuante por vez: abrir o painel de filtros fecha
    // as sugestões de busca e o menu, se houver.
    if (_suggestions.isNotEmpty) {
      setState(() => _suggestions = []);
    }
    _closeMenu();

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

  bool get _hasActiveFilters =>
      _timeFilter != IncidentTimeFilter.all ||
      _distanceFilter != IncidentDistanceFilter.all ||
      _activeFilters.length != IncidentSeverity.values.length ||
      _activeCategories.length != _allCategories.length;

  Widget _buildActiveFilterChips(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final chips = <Widget>[];

    if (_timeFilter != IncidentTimeFilter.all) {
      chips.add(_ActiveFilterChip(
        label: _timeFilterLabel(loc, _timeFilter),
        onRemove: () => setState(() => _timeFilter = IncidentTimeFilter.all),
      ));
    }
    if (_distanceFilter != IncidentDistanceFilter.all) {
      chips.add(_ActiveFilterChip(
        label: _distanceFilterLabel(loc, _distanceFilter),
        onRemove: () =>
            setState(() => _distanceFilter = IncidentDistanceFilter.all),
      ));
    }
    if (_activeFilters.length != IncidentSeverity.values.length) {
      for (final s in List<IncidentSeverity>.of(_activeFilters)) {
        chips.add(_ActiveFilterChip(
          label: SeverityColors.label(context, s),
          color: SeverityColors.of(s),
          onRemove: () => setState(() => _activeFilters.remove(s)),
        ));
      }
    }
    if (_activeCategories.length != _allCategories.length) {
      for (final c in List<String>.of(_activeCategories)) {
        chips.add(_ActiveFilterChip(
          label: ReportLabels.category(context, c),
          onRemove: () => setState(() => _activeCategories.remove(c)),
        ));
      }
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chip in chips)
            Padding(padding: const EdgeInsets.only(right: 8), child: chip),
        ],
      ),
    );
  }

  static String _timeFilterLabel(AppLocalizations loc, IncidentTimeFilter f) {
    switch (f) {
      case IncidentTimeFilter.lastHour:
        return loc.timeFilterLastHour;
      case IncidentTimeFilter.last6Hours:
        return loc.timeFilterLast6Hours;
      case IncidentTimeFilter.last24Hours:
        return loc.timeFilterLast24Hours;
      case IncidentTimeFilter.all:
        return loc.timeFilterAllTime;
    }
  }

  static String _distanceFilterLabel(
      AppLocalizations loc, IncidentDistanceFilter f) {
    switch (f) {
      case IncidentDistanceFilter.m250:
        return loc.distanceFilter250m;
      case IncidentDistanceFilter.m500:
        return loc.distanceFilter500m;
      case IncidentDistanceFilter.km1:
        return loc.distanceFilter1km;
      case IncidentDistanceFilter.all:
        return loc.distanceFilterAny;
    }
  }

  // Painel de filtros com estado "staged": as escolhas só valem de verdade
  // quando o usuário aperta Aplicar. Fechar pelo fundo/Esc descarta o que
  // foi mexido, igual Google Maps/Waze.
  Widget _buildFiltersContent() {
    IncidentTimeFilter pendingTime = _timeFilter;
    IncidentDistanceFilter pendingDistance = _distanceFilter;
    final pendingSeverity = Set<IncidentSeverity>.of(_activeFilters);
    final pendingCategories = Set<String>.of(_activeCategories);

    return StatefulBuilder(
      builder: (context, setModalState) {
        final loc = AppLocalizations.of(context)!;
        final now = DateTime.now();
        final distanceFrom =
            _userCurrentLocation ?? _initialCenter ?? _mapCenter;

        int previewCount() {
          return _incidents.where((i) {
            if (!pendingSeverity.contains(i.severity)) return false;
            if (!i.isOfficial && !pendingCategories.contains(i.category)) {
              return false;
            }
            switch (pendingTime) {
              case IncidentTimeFilter.lastHour:
                if (!i.dateTime
                    .isAfter(now.subtract(const Duration(hours: 1)))) {
                  return false;
                }
                break;
              case IncidentTimeFilter.last6Hours:
                if (!i.dateTime
                    .isAfter(now.subtract(const Duration(hours: 6)))) {
                  return false;
                }
                break;
              case IncidentTimeFilter.last24Hours:
                if (!i.dateTime
                    .isAfter(now.subtract(const Duration(hours: 24)))) {
                  return false;
                }
                break;
              case IncidentTimeFilter.all:
                break;
            }
            if (pendingDistance != IncidentDistanceFilter.all) {
              final meters =
                  _distanceCalc.as(LengthUnit.Meter, distanceFrom, i.location);
              switch (pendingDistance) {
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
          }).length;
        }

        Widget section(String title, Widget child) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              child,
              const SizedBox(height: 20),
            ],
          );
        }

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    loc.filters,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 20),
                section(
                  loc.filterTimeSectionTitle,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: IncidentTimeFilter.values.map((f) {
                      return ChoiceChip(
                        label: Text(_timeFilterLabel(loc, f)),
                        selected: pendingTime == f,
                        onSelected: (_) => setModalState(() => pendingTime = f),
                      );
                    }).toList(),
                  ),
                ),
                section(
                  loc.distanceLabel,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: IncidentDistanceFilter.values.map((f) {
                      return ChoiceChip(
                        label: Text(_distanceFilterLabel(loc, f)),
                        selected: pendingDistance == f,
                        onSelected: (_) =>
                            setModalState(() => pendingDistance = f),
                      );
                    }).toList(),
                  ),
                ),
                section(
                  loc.sectionSeverity,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: IncidentSeverity.values.map((s) {
                      final color = SeverityColors.of(s);
                      final selected = pendingSeverity.contains(s);
                      return FilterChip(
                        label: Text(SeverityColors.label(context, s)),
                        selected: selected,
                        selectedColor: color.withValues(alpha: 0.18),
                        checkmarkColor: color,
                        side: BorderSide(color: color.withValues(alpha: 0.4)),
                        onSelected: (sel) => setModalState(() {
                          if (sel) {
                            pendingSeverity.add(s);
                          } else {
                            pendingSeverity.remove(s);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ),
                section(
                  loc.sectionCategory,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allCategories.map((c) {
                      final selected = pendingCategories.contains(c);
                      return FilterChip(
                        avatar: Icon(ReportIcons.category(c), size: 16),
                        label: Text(ReportLabels.category(context, c)),
                        selected: selected,
                        onSelected: (sel) => setModalState(() {
                          if (sel) {
                            pendingCategories.add(c);
                          } else {
                            pendingCategories.remove(c);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ),
                Center(
                  child: Text(
                    loc.filterResultCount(previewCount()),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: BeeAwareTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setModalState(() {
                          pendingTime = IncidentTimeFilter.all;
                          pendingDistance = IncidentDistanceFilter.all;
                          pendingSeverity
                            ..clear()
                            ..addAll(IncidentSeverity.values);
                          pendingCategories
                            ..clear()
                            ..addAll(_allCategories);
                        }),
                        child: Text(loc.clearFilters),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _timeFilter = pendingTime;
                            _distanceFilter = pendingDistance;
                            _activeFilters
                              ..clear()
                              ..addAll(pendingSeverity);
                            _activeCategories
                              ..clear()
                              ..addAll(pendingCategories);
                          });
                          _filterOverlay?.remove();
                          _filterOverlay = null;
                        },
                        child: Text(loc.applyFilters),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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

  void _openMenu(BuildContext context) {
    _clearHint();
    final rootContext = context; // 👈 importante para evitar erros

    // Só uma superfície flutuante por vez: abrir o menu fecha sugestões e
    // o painel de filtros, se houver — mesma disciplina do resto do mapa.
    if (_suggestions.isNotEmpty) {
      setState(() => _suggestions = []);
    }
    if (_filterOverlay != null) {
      _filterOverlay!.remove();
      _filterOverlay = null;
    }
    _closeMenu();

    _menuOverlay = OverlayEntry(
      builder: (overlayContext) {
        return GestureDetector(
          onTap: _closeMenu,
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
                    child: _buildMenuContent(overlayContext, rootContext),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_menuOverlay!);
  }

  Widget _buildMenuContent(
      BuildContext overlayContext, BuildContext rootContext) {
    final loc = AppLocalizations.of(overlayContext)!;
    final tokens = rootContext.read<TokenState>().tokens;
    final user = Supabase.instance.client.auth.currentUser;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(overlayContext).size.height * 0.8,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ================= HEADER =================
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  _closeMenu();

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    color: BeeAwareTheme.primary.withValues(alpha: 0.06),
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

            _menuSectionLabel(loc.menuSectionAccount),

            // ================= BUY =================
            if (AppConfig.tokensEnabled)
              _menuItem(
                icon: PhosphorIconsRegular.creditCard,
                label: loc.buyMoreCredits,
                onTap: () {
                  _closeMenu();
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
                _closeMenu();
              },
            ),

            const SizedBox(height: 20),

            _menuSectionLabel(loc.menuSectionSupport),

            // ================= DATA =================
            _menuItem(
              icon: PhosphorIconsRegular.chartBar,
              label: loc.dataSources,
              onTap: () {
                _closeMenu();
                _showOfficialLegendSheet(rootContext);
              },
            ),

            _menuItem(
              icon: PhosphorIconsRegular.globe,
              label: loc.languageLabel,
              onTap: () {
                _closeMenu();
                _showLanguagePicker(rootContext);
              },
            ),

            _menuItem(
              icon: PhosphorIconsRegular.shieldCheck,
              label: loc.privacyLabel,
              onTap: () async {
                _closeMenu();

                final uri = Uri.parse('https://www.beeaware.io/privacy.html');

                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),

            _menuItem(
              icon: PhosphorIconsRegular.info,
              label: loc.aboutBeeAware,
              onTap: () {
                _closeMenu();
                _showAboutSheet(rootContext);
              },
            ),

            // ================= LOGOUT =================
            if (user != null) ...[
              const SizedBox(height: 20),
              _menuItem(
                icon: PhosphorIconsRegular.signOut,
                label: loc.signOut,
                onTap: () async {
                  await Supabase.instance.client.auth.signOut();
                  _closeMenu();
                  setState(() {}); // ou atualize o state do menu
                  rootContext.read<TokenState>().clear();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Mesma tipografia de título de seção do painel de filtros
  // (_buildFiltersContent) — os dois cartões flutuantes da barra usam
  // agora a mesma linguagem, em vez do rótulo pequeno em caixa alta que o
  // menu tinha antes.
  Widget _menuSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: BeeAwareTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  // Mesmo círculo com o ícone tingido de âmbar usado em ReportSummaryScreen
  // e ReportDateTimeScreen — o menu usava um ListTile puro, sem nenhuma
  // cor ou avatar, destoando do resto do app.
  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
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
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            const Icon(
              PhosphorIconsRegular.caretRight,
              size: 18,
              color: BeeAwareTheme.textAux,
            ),
          ],
        ),
      ),
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
    // UkPoliceApi só cobre o Reino Unido — fora dele (Brasil, etc.) isso
    // sempre vem vazio. Sem esse fallback, `.last` lançava em lista vazia
    // e a função inteira abortava antes de chamar _openTrendOverlay: o
    // botão de tendência simplesmente não fazia nada.
    final last =
        policeTrend.isNotEmpty ? policeTrend.last.month : DateTime.now();

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

// Controle de zoom flutuante — pill meio-transparente com um slider
// vertical "graduado" entre os limites de zoom do mapa, mais os botões
// +/- nas pontas. Reflete zoom feito por pinça/scroll (via
// mapEventStream), não só o que o próprio slider disparou.
class _ZoomControl extends StatefulWidget {
  final MapController mapController;

  const _ZoomControl({required this.mapController});

  @override
  State<_ZoomControl> createState() => _ZoomControlState();
}

class _ZoomControlState extends State<_ZoomControl> {
  static const double _minZoom = 3;
  static const double _maxZoom = 18;

  late double _zoom =
      widget.mapController.camera.zoom.clamp(_minZoom, _maxZoom);
  StreamSubscription<MapEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.mapController.mapEventStream.listen((event) {
      final z = event.camera.zoom.clamp(_minZoom, _maxZoom);
      if (mounted && (z - _zoom).abs() > 0.01) {
        setState(() => _zoom = z);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _setZoom(double value) {
    final clamped = value.clamp(_minZoom, _maxZoom);
    setState(() => _zoom = clamped);
    widget.mapController.move(widget.mapController.camera.center, clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(PhosphorIconsRegular.plus, size: 16),
            color: BeeAwareTheme.primary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _zoom < _maxZoom ? () => _setZoom(_zoom + 1) : null,
          ),
          SizedBox(
            height: 140,
            width: 32,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: SliderComponentShape.noOverlay,
                  activeTrackColor: BeeAwareTheme.primary,
                  inactiveTrackColor:
                      BeeAwareTheme.primary.withValues(alpha: 0.25),
                  thumbColor: BeeAwareTheme.primary,
                ),
                child: Slider(
                  min: _minZoom,
                  max: _maxZoom,
                  value: _zoom,
                  onChanged: _setZoom,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsRegular.minus, size: 16),
            color: BeeAwareTheme.primary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _zoom > _minZoom ? () => _setZoom(_zoom - 1) : null,
          ),
        ],
      ),
    );
  }
}

// Botão de SOS da barra inferior — vermelho e com texto sempre visível,
// nunca só um ícone de sirene: é a única ação de emergência da barra e
// precisa ser reconhecível sem hover/tooltip.
// Chip removível de filtro ativo, mostrado sobre o mapa (ver
// _buildActiveFilterChips) — mesmo estilo pill branca já usado na legenda
// de severidade e no badge de tokens da busca.
class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final Color? color;
  final VoidCallback onRemove;

  const _ActiveFilterChip({
    required this.label,
    required this.onRemove,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? BeeAwareTheme.primary;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onRemove,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c,
                ),
              ),
              const SizedBox(width: 4),
              Icon(PhosphorIconsRegular.x, size: 14, color: c),
            ],
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

/// Route Awareness comparison card (roadmap 9.5/13.3) — shown once
/// _searchRoutes finds results. Naming rule enforced here, the one place
/// route counts turn into words: only ever "Faster: X" and "Fewer recent
/// safety signals: Y", never a third invented "Safest: X" label
/// (RouteAwarenessApi/route-awareness itself never computes or returns
/// anything like a safety score, on purpose — see that function's own
/// header).
class _RouteResultsCard extends StatelessWidget {
  final List<RouteOption> routes;
  final List<Color> colors;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<String> onOpenInApp;

  const _RouteResultsCard({
    required this.routes,
    required this.colors,
    required this.selectedIndex,
    required this.onSelect,
    required this.onOpenInApp,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final fastest =
        routes.reduce((a, b) => a.durationSeconds <= b.durationSeconds ? a : b);
    final fewerSignals = routes
        .reduce((a, b) => a.totalSignalCount <= b.totalSignalCount ? a : b);
    final signalsTie = routes
        .every((r) => r.totalSignalCount == routes.first.totalSignalCount);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: BeeAwareTheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: BeeAwareTheme.border),
        boxShadow: BeeAwareTheme.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < routes.length; i++) ...[
            _RouteResultRow(
              color: colors[i % colors.length],
              label: loc.routeAwarenessRouteLabel(String.fromCharCode(65 + i)),
              route: routes[i],
              selected: i == selectedIndex,
              onTap: routes.length > 1 ? () => onSelect(i) : null,
            ),
            if (i < routes.length - 1) const Divider(height: 14),
          ],
          if (routes.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              loc.routeAwarenessFastest(loc.routeAwarenessRouteLabel(
                  String.fromCharCode(65 + routes.indexOf(fastest)))),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BeeAwareTheme.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              signalsTie
                  ? loc.routeAwarenessSimilarSignals
                  : loc.routeAwarenessFewerSignals(loc.routeAwarenessRouteLabel(
                      String.fromCharCode(65 + routes.indexOf(fewerSignals)))),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BeeAwareTheme.textPrimary),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Text(
            loc.routeAwarenessOpenInApp,
            style: const TextStyle(
                fontSize: 11, color: BeeAwareTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _ExternalMapButton(
                label: loc.routeAwarenessGoogleMaps,
                onTap: () => onOpenInApp('google'),
              ),
              const SizedBox(width: 8),
              _ExternalMapButton(
                label: loc.routeAwarenessWaze,
                onTap: () => onOpenInApp('waze'),
              ),
              const SizedBox(width: 8),
              _ExternalMapButton(
                label: loc.routeAwarenessAppleMaps,
                onTap: () => onOpenInApp('apple'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExternalMapButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ExternalMapButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(PhosphorIconsRegular.navigationArrow, size: 15),
        label: Text(
          label,
          style: const TextStyle(fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          side: const BorderSide(color: BeeAwareTheme.border),
        ),
      ),
    );
  }
}

class _RouteResultRow extends StatelessWidget {
  final Color color;
  final String label;
  final RouteOption route;
  final bool selected;
  final VoidCallback? onTap;

  const _RouteResultRow({
    required this.color,
    required this.label,
    required this.route,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final minutes = (route.durationSeconds / 60).round();
    final km = route.distanceMeters / 1000;
    final distanceLabel = km >= 1
        ? '${km.toStringAsFixed(1)} km'
        : '${route.distanceMeters.round()} m';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: onTap != null
              ? Border.all(
                  color: selected ? color : Colors.transparent, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? PhosphorIconsRegular.checkCircle
                  : PhosphorIconsRegular.circle,
              size: 18,
              color: selected ? color : BeeAwareTheme.textAux,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(
                    '$minutes min · $distanceLabel',
                    style: const TextStyle(
                        fontSize: 12, color: BeeAwareTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              loc.areaIntelligenceSignalCount(route.totalSignalCount),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: route.totalSignalCount > 0
                    ? BeeAwareTheme.textPrimary
                    : BeeAwareTheme.textAux,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live-as-you-type address results for one Route Awareness field
/// (_buildRouteSearchBar) — same two-line primary/secondary display the
/// main search's own suggestions dropdown uses, inline rather than a
/// floating overlay since the route panel isn't itself floating loose
/// over the map the way the plain search bar's dropdown is.
class _RouteFieldSuggestions extends StatelessWidget {
  final List<AddressSuggestion> suggestions;
  final ValueChanged<AddressSuggestion> onSelected;

  const _RouteFieldSuggestions({
    required this.suggestions,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 180),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final s = suggestions[index];
          return ListTile(
            dense: true,
            leading: const Icon(PhosphorIconsRegular.mapPin, size: 18),
            title: Text(
              s.primary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: s.secondary.isEmpty
                ? null
                : Text(
                    s.secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: BeeAwareTheme.textSecondary),
                  ),
            onTap: () => onSelected(s),
          );
        },
      ),
    );
  }
}
