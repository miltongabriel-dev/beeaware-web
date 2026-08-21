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
/// Only ROAD_SAFETY events exist today (PRF's normalize() is the only one
/// of the four Brazil adapters that's implemented) — VIOLENCE/PROPERTY/
/// PUBLIC_SAFETY rows will start flowing through this same path once
/// SINESP/RENAEST's normalize() is filled in, with no client change
/// needed. Rows without a real point location never reach this table (the
/// RPC excludes them), so there's no separate "don't invent precision"
/// check needed client-side.
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

    return MapIncident(
      id: 'br-security-event-$id',
      location: LatLng(lat, lng),
      severity: severity,
      category: eventType,
      subcategory: (row['original_category'] as String?) ?? eventType,
      description: loc.roadAccidentDescription(
        (row['original_category'] as String?) ?? loc.roadAccidentCategory,
        city,
        state,
      ),
      dateTime:
          occurredAt != null ? DateTime.parse(occurredAt) : DateTime.now(),
      isOfficial: sourceType == 'official',
      source: 'PRF',
    );
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
