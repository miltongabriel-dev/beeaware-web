import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/news_api.dart';
import '../config/emergency_numbers.dart';
import '../l10n/app_localizations.dart';
import '../map/incident_store.dart';
import '../map/map_incident.dart';
import '../report/report_category_screen.dart';
import '../report/report_icons.dart';
import '../report/report_labels.dart';
import '../theme/app_card.dart';
import '../theme/beeaware_theme.dart';
import '../theme/emergency_sos.dart';
import '../utils/geocoding.dart';
import '../utils/preferred_country_code.dart';
import '../utils/relative_time.dart';
import 'widgets/incident_bottom_sheet.dart';

/// The "Início" tab: greeting, current location, a full-width "Reportar"
/// CTA, a short line on where the data comes from, and a "Atividade
/// recente" feed of the nearest incidents. Unlike the Mapa tab, this
/// screen never triggers its own incident fetch — it only reads whatever
/// IncidentStore already holds (Mapa's own periodic sync keeps that fresh
/// regardless of which tab is active, since both stay mounted via the
/// IndexedStack in RootScreen).
class HomeDashboardScreen extends StatefulWidget {
  final VoidCallback onOpenAlerts;
  final void Function(LatLng? point) onOpenMap;

  const HomeDashboardScreen({
    super.key,
    required this.onOpenAlerts,
    required this.onOpenMap,
  });

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  static const Distance _distanceCalc = Distance();
  static const int _maxItems = 10;

  LatLng? _userLocation;
  String? _locationLabel;
  bool _locationLoading = true;

  List<MapIncident> _incidents = List.unmodifiable(const []);
  StreamSubscription<List<MapIncident>>? _subscription;

  List<NewsItem> _news = const [];
  bool _newsLoaded = false;

  @override
  void initState() {
    super.initState();
    _subscription = IncidentStore.stream.listen((data) {
      if (!mounted) return;
      setState(() => _incidents = data);
    });
    _loadLocation();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _loadLocation() async {
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
        final point = LatLng(position.latitude, position.longitude);
        if (!mounted) return;
        setState(() => _userLocation = point);
        _loadNews(point);

        final label = await reverseGeocode(point);
        if (!mounted) return;
        setState(() {
          _locationLabel = label;
          _locationLoading = false;
        });
        return;
      }
    } catch (_) {
      // Falls through to the "unavailable" state below — the Mapa tab is
      // where permission-denied/blocked get their own explicit messaging;
      // here it just means the activity feed sorts by recency instead of
      // distance (see _nearestIncidents).
    }

    if (mounted) setState(() => _locationLoading = false);
  }

  /// Lets the user search for and pick any address instead of only ever
  /// seeing their live GPS position — the location pill was read-only
  /// before this, with the crosshair button only able to re-fetch the
  /// device's real position. The crosshair still does exactly that
  /// (via _loadLocation), so picking an address here is a temporary
  /// override, not a permanent replacement of "where I actually am".
  Future<void> _openAddressPicker() async {
    // _AddressPickerSheet gives itself a fixed height (see its own header
    // for why) instead of sizing to its content, so no extra constraint
    // is needed here.
    final selected = await showModalBottomSheet<AddressSuggestion>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => const _AddressPickerSheet(),
    );
    if (selected == null || !mounted) return;

    setState(() {
      _userLocation = selected.point;
      _locationLabel = selected.full;
      _locationLoading = false;
    });
    _loadNews(selected.point);
  }

  // Resolves its own state name via reverseGeocode rather than trusting
  // whatever _locationLabel already holds — a picked address's own label
  // (AddressSuggestion.full) isn't in the same "City, State" shape
  // reverseGeocode produces, and this hint has to be right for it to be
  // useful at all (see NewsApi.fetchNearby's own doc comment for why it
  // exists: some Brazilian states, e.g. Rondônia, have zero backfilled
  // municipality geometry, so this external geocode is the only thing
  // that can place a point in them).
  Future<void> _loadNews(LatLng point) async {
    final label = await reverseGeocode(point);
    final stateHint =
        label != null && label.contains(',')
            ? label.substring(label.lastIndexOf(',') + 1).trim()
            : null;

    final items = await NewsApi.fetchNearby(point, stateNameHint: stateHint);
    if (!mounted) return;
    setState(() {
      _news = items;
      _newsLoaded = true;
    });
  }

  Future<void> _openArticle(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _displayName(AppLocalizations loc) {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null || email.isEmpty) return loc.homeGreetingGeneric;

    final localPart = email.split('@').first.replaceAll(RegExp(r'[._]'), ' ').trim();
    final words = localPart.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return loc.homeGreetingGeneric;
    final firstWord = words.first;

    final capitalized = firstWord[0].toUpperCase() + firstWord.substring(1);
    return loc.homeGreeting(capitalized);
  }

  List<MapIncident> _nearestIncidents() {
    final list = List<MapIncident>.from(_incidents);
    final origin = _userLocation;

    if (origin != null) {
      list.sort((a, b) => _distanceCalc
          .as(LengthUnit.Meter, origin, a.location)
          .compareTo(_distanceCalc.as(LengthUnit.Meter, origin, b.location)));
    } else {
      list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    }

    return list.take(_maxItems).toList();
  }

  /// Best available scope name for the news section's title. A GB row has
  /// no state_code at all (BbcNewsAdapter is country-wide — see its own
  /// header for why), so it's checked first and always labelled "United
  /// Kingdom"/"Reino Unido" — never the UK city/county Nominatim resolved
  /// for the location pill, which would overstate the precision this
  /// source actually has. For Brazil, prefers the free-text state
  /// Nominatim already resolved (the part after the last comma in "City,
  /// State") — available as soon as reverseGeocode() returns, whether or
  /// not any news exists yet for that state — falling back to the state
  /// code carried by an actual news row for the rare case the news fetch
  /// resolves first; empty only when nothing has resolved yet.
  String get _newsStateLabel {
    if (_news.isNotEmpty && _news.first.countryCode == 'GB') {
      return AppLocalizations.of(context)!.unitedKingdomLabel;
    }

    final label = _locationLabel;
    if (label != null && label.contains(',')) {
      return label.substring(label.lastIndexOf(',') + 1).trim();
    }
    if (_news.isNotEmpty) {
      final stateCode = _news.first.stateCode;
      if (stateCode != null) return brazilianStateNames[stateCode] ?? stateCode;
    }
    return '';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  void _openReport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReportCategoryScreen()),
    );
  }

  void _openIncident(MapIncident incident) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IncidentBottomSheet(incident: incident),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final nearest = _nearestIncidents();

    return Scaffold(
      backgroundColor: BeeAwareTheme.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
          children: [
            Row(
              children: [
                SvgPicture.asset(
                  'assets/logo/beeaware_symbol.svg',
                  width: 32,
                  height: 32,
                ),
                const SizedBox(width: AppSpacing.sm),
                const Text(
                  'BeeAware',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: BeeAwareTheme.primary,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                SosButton(
                  label: loc.sosBarLabel(
                      emergencyNumbersFor(preferredCountryCode(_userLocation))
                          .primary),
                  onTap: () => showEmergencySheet(
                      context, preferredCountryCode(_userLocation)),
                ),
                const SizedBox(width: AppSpacing.sm),
                GestureDetector(
                  onTap: widget.onOpenAlerts,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: BeeAwareTheme.surface,
                      shape: BoxShape.circle,
                      boxShadow: BeeAwareTheme.cardShadow,
                    ),
                    child: const Icon(
                      PhosphorIconsRegular.bell,
                      color: BeeAwareTheme.textPrimary,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              _displayName(loc),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: BeeAwareTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              loc.homeSubtitle,
              style: const TextStyle(
                fontSize: 14,
                color: BeeAwareTheme.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Localização — só leitura; buscar um endereço específico
            // continua sendo função da aba Mapa. Pílula + botão circular
            // separado (em vez de um único card) para casar com a
            // referência; o botão redispara _loadLocation.
            Row(
              children: [
                Expanded(
                  child: AppCard(
                    onTap: _openAddressPicker,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                    border: Border.all(color: Colors.transparent),
                    child: Row(
                      children: [
                        const Icon(PhosphorIconsRegular.mapPin,
                            color: BeeAwareTheme.primary, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            _locationLoading
                                ? loc.homeLocationLoading
                                : (_locationLabel ?? loc.homeLocationUnavailable),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: BeeAwareTheme.textPrimary,
                            ),
                          ),
                        ),
                        const Icon(PhosphorIconsRegular.pencilSimple,
                            color: BeeAwareTheme.textAux, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                GestureDetector(
                  onTap: () {
                    setState(() => _locationLoading = true);
                    _loadLocation();
                  },
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: BeeAwareTheme.surface,
                      shape: BoxShape.circle,
                      boxShadow: BeeAwareTheme.cardShadow,
                    ),
                    child: const Icon(PhosphorIconsRegular.crosshairSimple,
                        color: BeeAwareTheme.textPrimary, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // CTA principal — Container próprio em vez do ElevatedButton
            // padrão do tema: precisa de mais raio de borda e mais altura
            // do que o resto do app usa para ganhar o peso visual de
            // destaque principal da tela.
            Material(
              color: BeeAwareTheme.primary,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _openReport,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          PhosphorIconsFill.flag,
                          color: BeeAwareTheme.textPrimary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.reportBarLabel,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: BeeAwareTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              loc.homeReportCta,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: BeeAwareTheme.textPrimary
                                    .withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            Text(
              loc.exploreSectionTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: BeeAwareTheme.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _MapPreviewCard(
              location: _userLocation,
              onTap: () => widget.onOpenMap(_userLocation),
            ),
            const SizedBox(height: AppSpacing.xl),

            Text(
              loc.areaIntelligenceRecent,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: BeeAwareTheme.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            if (nearest.isEmpty)
              Text(
                loc.recentActivityEmpty,
                style: const TextStyle(
                  fontSize: 13,
                  color: BeeAwareTheme.textSecondary,
                ),
              )
            else
              for (final incident in nearest) ...[
                _ActivityItem(
                  incident: incident,
                  distanceLabel: _userLocation == null
                      ? null
                      : loc.distanceAway(_formatDistance(_distanceCalc.as(
                          LengthUnit.Meter, _userLocation!, incident.location))),
                  onTap: () => _openIncident(incident),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

            // News is a genuinely different scope from everything above —
            // Atividade Recente is sorted by real distance in metres,
            // this is whatever G1NewsAdapter classified anywhere in the
            // user's whole STATE (see g1_news.ts's header on why: the
            // source's own precision stops there). Kept in its own titled
            // section rather than merged into the list above so that
            // difference in scope is never implied to be "nearby" —
            // labelling it by state name is the whole point, not a detail.
            if (_newsLoaded) ...[
              const SizedBox(height: AppSpacing.xl),
              Text(
                loc.newsSectionTitle(_newsStateLabel),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: BeeAwareTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                loc.newsSectionSubtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: BeeAwareTheme.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_news.isEmpty)
                Text(
                  loc.newsSectionEmpty,
                  style: const TextStyle(
                    fontSize: 13,
                    color: BeeAwareTheme.textSecondary,
                  ),
                )
              else
                for (final item in _news) ...[
                  _NewsCard(
                    item: item,
                    onTap: item.articleUrl == null
                        ? null
                        : () => _openArticle(item.articleUrl!),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Replaces the old "Explorar" 3-card grid (Dados públicos/Notícias/
/// Comunidade, all dead ends with no real screen behind them) with a real
/// shortcut: a small non-interactive snapshot of the map tiles around the
/// user, tapping through to the actual Mapa tab.
///
/// This stitches a handful of OSM raster tiles into a Stack rather than
/// embedding a second live `FlutterMap` — the Mapa tab already runs one
/// full interactive map (its own MapController, tile cache, incident
/// clustering); mounting a second live map here (IndexedStack keeps every
/// tab mounted at once) would double tile-fetching and memory for a
/// thumbnail that's never panned or zoomed. Standard slippy-map tile math
/// (see _lonToTileX/_latToTileY) positions the stitched tiles so the
/// user's exact coordinate lands under the fixed center pin, rather than
/// just centering on whichever tile happens to contain it.
class _MapPreviewCard extends StatelessWidget {
  static const int _zoom = 15;
  static const double _tileSize = 256;
  static const double _height = 150;

  final LatLng? location;
  final VoidCallback onTap;

  const _MapPreviewCard({required this.location, required this.onTap});

  static double _lonToTileX(double lon, int z) =>
      (lon + 180.0) / 360.0 * (1 << z);

  static double _latToTileY(double lat, int z) {
    final latRad = lat * math.pi / 180.0;
    return (1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
        2.0 *
        (1 << z);
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      border: Border.all(color: Colors.transparent),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: SizedBox(
          height: _height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (location == null)
                Container(color: BeeAwareTheme.background)
              else
                LayoutBuilder(
                  builder: (context, constraints) => _tileGrid(
                    location!,
                    constraints.maxWidth,
                    _height,
                  ),
                ),
              const Center(
                child: Icon(
                  PhosphorIconsFill.mapPin,
                  color: BeeAwareTheme.primary,
                  size: 34,
                ),
              ),
              Positioned(
                left: AppSpacing.md,
                bottom: AppSpacing.md,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.mapPreviewOpenHint,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: BeeAwareTheme.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tileGrid(LatLng point, double width, double height) {
    final xTile = _lonToTileX(point.longitude, _zoom);
    final yTile = _latToTileY(point.latitude, _zoom);

    // Top-left corner of the viewport, in fractional tile coordinates —
    // everything below just draws whichever tiles overlap this window and
    // places them at the pixel offset that keeps (xTile, yTile) exactly
    // under the box's center, where the pin above is drawn.
    final viewportLeft = xTile - (width / 2) / _tileSize;
    final viewportTop = yTile - (height / 2) / _tileSize;

    final firstCol = viewportLeft.floor();
    final firstRow = viewportTop.floor();
    final lastCol = (viewportLeft + width / _tileSize).floor();
    final lastRow = (viewportTop + height / _tileSize).floor();
    final tileCount = 1 << _zoom;

    final tiles = <Widget>[];
    for (var row = firstRow; row <= lastRow; row++) {
      if (row < 0 || row >= tileCount) continue;
      for (var col = firstCol; col <= lastCol; col++) {
        final wrappedCol = col % tileCount;
        tiles.add(Positioned(
          left: (col - viewportLeft) * _tileSize,
          top: (row - viewportTop) * _tileSize,
          width: _tileSize,
          height: _tileSize,
          child: Image.network(
            'https://tile.openstreetmap.org/$_zoom/$wrappedCol/$row.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: BeeAwareTheme.background),
          ),
        ));
      }
    }

    return Stack(children: tiles);
  }
}

Color _newsSeverityColor(String? severity) {
  switch (severity) {
    case 'high':
      return SeverityColors.high;
    case 'medium':
      return SeverityColors.medium;
    case 'low':
      return SeverityColors.low;
    default:
      return SeverityColors.medium;
  }
}

/// A news-derived card — visually similar to [_ActivityItem] (same
/// severity-coloured circle, same two-line layout) but with a newspaper
/// icon instead of the community/official ones, and a headline + source
/// byline instead of a category label, since what this card is showing is
/// fundamentally an article, not a normalized incident record. Tapping it
/// opens the real article (url_launcher, externalApplication) — a real
/// link a user can independently verify is exactly what this project's
/// news source, and only this source, can actually offer.
class _NewsCard extends StatelessWidget {
  final NewsItem item;
  final VoidCallback? onTap;

  const _NewsCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final categoryLabel = ReportLabels.officialCategory(context, item.eventCategory);
    final byline = [
      item.sourceOrganisation,
      if (item.subtitle != null && item.subtitle!.isNotEmpty) item.subtitle,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      border: Border.all(color: Colors.transparent),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _newsSeverityColor(item.severity),
            ),
            child: const Icon(
              PhosphorIconsFill.newspaperClipping,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      categoryLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: BeeAwareTheme.textAux,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      relativeTime(context, item.occurredAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: BeeAwareTheme.textAux,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: BeeAwareTheme.textPrimary,
                  ),
                ),
                if (byline.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    byline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: BeeAwareTheme.textSecondary,
                    ),
                  ),
                ],
                if (onTap != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    loc.newsReadArticle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: BeeAwareTheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Search-and-pick address sheet opened by tapping the Início location
/// pill. Reuses fetchAddressSuggestions (geocoding.dart) — the same
/// Brazil-and-UK-aware live-suggestions endpoint the Mapa tab's search box
/// already calls — rather than introducing a second geocoding path.
class _AddressPickerSheet extends StatefulWidget {
  const _AddressPickerSheet();

  @override
  State<_AddressPickerSheet> createState() => _AddressPickerSheetState();
}

class _AddressPickerSheetState extends State<_AddressPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<AddressSuggestion> _suggestions = const [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _loading = true);
      final results = await fetchAddressSuggestions(value);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final keyboardHeight = media.viewInsets.bottom;

    // A fixed height, not just a max — with mainAxisSize.min the sheet
    // used to size itself to however many suggestions came back, so the
    // search field (sharing the same Column) physically moved up and down
    // the screen on every keystroke: short with 0 results, tall with 10,
    // occasionally tall enough to push itself off the top of the screen
    // entirely. Deriving this once from the screen size and current
    // keyboard height (not from _suggestions.length) keeps the field's
    // position constant; only the space below it — via Expanded — grows
    // or shrinks, scrolling internally instead of resizing the sheet.
    final availableAboveKeyboard =
        media.size.height - keyboardHeight - media.padding.top;
    final contentHeight = (availableAboveKeyboard * 0.65)
        .clamp(0.0, availableAboveKeyboard)
        .toDouble();
    final sheetHeight = contentHeight + keyboardHeight;

    return SizedBox(
      height: sheetHeight,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.md,
          bottom: keyboardHeight + AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: BeeAwareTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: loc.searchAnAddressHint,
                prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
                filled: true,
                fillColor: BeeAwareTheme.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _onChanged,
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : _suggestions.isEmpty
                      ? const SizedBox.shrink()
                      : ListView.builder(
                          itemCount: _suggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = _suggestions[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(PhosphorIconsRegular.mapPin,
                                  color: BeeAwareTheme.primary),
                              title: Text(
                                suggestion.primary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: suggestion.secondary.isEmpty
                                  ? null
                                  : Text(
                                      suggestion.secondary,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              onTap: () => Navigator.pop(context, suggestion),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final MapIncident incident;
  final String? distanceLabel;
  final VoidCallback onTap;

  const _ActivityItem({
    required this.incident,
    required this.distanceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final categoryLabel = incident.isOfficial
        ? ReportLabels.officialCategory(context, incident.officialEventCategory)
        : ReportLabels.category(context, incident.category);

    final place = incident.isOfficial
        ? [incident.officialCity, incident.officialState]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(', ')
        : incident.description;

    final subtitleParts = [
      if (distanceLabel != null) distanceLabel!,
      if (place.trim().isNotEmpty) place.trim(),
    ];

    final severityColor = SeverityColors.of(incident.severity);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      border: Border.all(color: Colors.transparent),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: severityColor,
            ),
            child: incident.isOfficial
                ? SvgPicture.asset(
                    'assets/icons/verified.svg',
                    width: 20,
                    height: 20,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  )
                : Icon(
                    ReportIcons.category(incident.category),
                    size: 20,
                    color: Colors.white,
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  categoryLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: BeeAwareTheme.textPrimary,
                  ),
                ),
                if (subtitleParts.isNotEmpty)
                  Text(
                    subtitleParts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: BeeAwareTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            relativeTime(context, incident.dateTime),
            style: const TextStyle(
              fontSize: 11,
              color: BeeAwareTheme.textAux,
            ),
          ),
        ],
      ),
    );
  }
}
