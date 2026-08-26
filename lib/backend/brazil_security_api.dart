import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../map/map_incident.dart';

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
      final rows = await _client.rpc('nearby_security_events', params: {
        'center_lat': lat,
        'center_lng': lng,
        'radius_meters': radiusMeters,
        'max_results': 300,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map(_toMapIncident)
          .whereType<MapIncident>()
          .toList();
    } catch (_) {
      // Offline-friendly by design, same as UkPoliceApi.
      return [];
    }
  }

  static MapIncident? _toMapIncident(Map<String, dynamic> row) {
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
    final eventCategory = row['event_category'] as String?;

    return MapIncident(
      id: 'br-security-event-$id',
      location: LatLng(lat, lng),
      severity: severity,
      category: eventType,
      subcategory: (row['original_category'] as String?) ?? eventType,
      // Left empty rather than pre-built here — IncidentBottomSheet
      // builds the actual sentence at render time from officialCity/
      // officialState/subcategory below, same reasoning as
      // officialEventCategory's own header (the sentence's "in"/"em"
      // connector is locale-dependent, so baking it in at fetch time had
      // the exact same staleness bug the category label did).
      description: '',
      dateTime:
          occurredAt != null ? DateTime.parse(occurredAt) : DateTime.now(),
      isOfficial: sourceType == 'official',
      source: row['source_organisation'] as String?,
      officialEventCategory: eventCategory,
      officialCity: city,
      officialState: state,
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
