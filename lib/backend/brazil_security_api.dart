import 'dart:ui' show PlatformDispatcher, Locale;

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../map/map_incident.dart';

/// Loads strings for the device's current locale without a BuildContext —
/// same pattern as UkPoliceApi, since this also runs from IncidentStore,
/// outside the widget tree.
Future<AppLocalizations> _loadLocalizations() {
  final deviceLocale = PlatformDispatcher.instance.locale;
  final resolved = deviceLocale.languageCode == 'en'
      ? const Locale('en')
      : const Locale('pt');
  return AppLocalizations.delegate.load(resolved);
}

/// Brazil-side equivalent of UkPoliceApi.fetchForArea: bounded read of the
/// BeeAware Brasil roadmap's security_events table (see
/// supabase/migrations/20260821170000_nearby_security_events_rpc.sql),
/// called from the same IncidentStore.syncOfficialForBounds flow that
/// already drives the UK official layer.
///
/// Now backed by 11 Brazil adapters across VIOLENCE/PROPERTY/PUBLIC_SAFETY/
/// ROAD_SAFETY, not just PRF's ROAD_SAFETY feed — nearby_security_events
/// (20260825160000) joins security_sources and returns source_organisation
/// per row so the client can attribute each pin to its real source instead
/// of assuming PRF. Rows without a real point location never reach this
/// table (the RPC excludes them), so there's no separate "don't invent
/// precision" check needed client-side.
class BrazilSecurityApi {
  static final SupabaseClient _client = Supabase.instance.client;

  static Future<List<MapIncident>> fetchForArea({
    required double lat,
    required double lng,
    required double radiusMeters,
  }) async {
    try {
      final loc = await _loadLocalizations();

      final rows = await _client.rpc('nearby_security_events', params: {
        'center_lat': lat,
        'center_lng': lng,
        'radius_meters': radiusMeters,
        'max_results': 300,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map((row) => _toMapIncident(row, loc))
          .whereType<MapIncident>()
          .toList();
    } catch (_) {
      // Offline-friendly by design, same as UkPoliceApi.
      return [];
    }
  }

  static MapIncident? _toMapIncident(
      Map<String, dynamic> row, AppLocalizations loc) {
    final location = row['location'];
    if (location is! Map) return null;
    final coords = location['coordinates'];
    if (coords is! List || coords.length < 2) return null;

    final lng = (coords[0] as num?)?.toDouble();
    final lat = (coords[1] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final id = row['id'] as String?;
    if (id == null) return null;

    final eventType = (row['event_type'] as String?) ?? 'accident';
    final severity = _mapSeverity(row['severity'] as String?);
    final city = (row['city'] as String?) ?? '';
    final state = (row['state'] as String?) ?? '';
    final occurredAt = row['occurred_at'] as String?;
    final sourceType = (row['source_type'] as String?) ?? 'official';
    final categoryLabel =
        _categoryLabel(row['event_category'] as String?, loc);

    return MapIncident(
      id: 'br-security-event-$id',
      location: LatLng(lat, lng),
      severity: severity,
      category: eventType,
      subcategory: (row['original_category'] as String?) ?? eventType,
      description: loc.officialEventDescription(
        (row['original_category'] as String?) ?? categoryLabel,
        city,
        state,
      ),
      dateTime:
          occurredAt != null ? DateTime.parse(occurredAt) : DateTime.now(),
      isOfficial: sourceType == 'official',
      source: row['source_organisation'] as String?,
      officialCategoryLabel: categoryLabel,
    );
  }

  /// event_category (security_event_category enum) -> display label.
  /// Reuses the community-report category strings where the concept lines
  /// up (VIOLENCE/PROPERTY) rather than inventing a parallel set of
  /// strings for the same real-world idea; PUBLIC_SAFETY falls back to the
  /// generic "Police report" bucket since none of the existing labels fit
  /// its mix (weapon/drugs/disturbance/fire/emergency) well enough to pick
  /// just one.
  static String _categoryLabel(String? eventCategory, AppLocalizations loc) {
    switch (eventCategory) {
      case 'ROAD_SAFETY':
        return loc.roadAccidentCategory;
      case 'VIOLENCE':
        return loc.categoryViolence;
      case 'PROPERTY':
        return loc.categoryTheft;
      default:
        return loc.policeReportCategory;
    }
  }

  static IncidentSeverity _mapSeverity(String? severity) {
    switch (severity) {
      case 'high':
        return IncidentSeverity.high;
      case 'medium':
        return IncidentSeverity.medium;
      default:
        return IncidentSeverity.low;
    }
  }
}
