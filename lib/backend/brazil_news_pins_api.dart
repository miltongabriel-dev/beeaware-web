import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../map/map_incident.dart';

/// News-derived map pins — a deliberately separate source from
/// BrazilSecurityApi.fetchForArea, not a relaxation of it.
///
/// nearby_security_events only ever returns EXACT/STREET rows (the
/// roadmap's geographic-honesty rule); news articles never carry a real
/// coordinate, only a city/state name match (geo_text_match.ts), so they
/// were never eligible there and only ever showed up in the separate
/// nearby_news text feed. nearby_news_pins (20260830120000) is the pin
/// equivalent for the subset of news that DID resolve to a real
/// municipality: it returns that municipality's polygon centroid as an
/// approximate point. Every MapIncident this produces is flagged
/// isApproximate so the pin renders as a halo/ring (BeeIncidentPin) and
/// the bottom sheet says so explicitly, instead of looking like a
/// confirmed exact-location record.
class BrazilNewsPinsApi {
  static final SupabaseClient _client = Supabase.instance.client;

  // Matches BrazilSecurityApi's own map-pin recency window so both
  // sources age out together.
  static const int _maxAgeDays = 60;

  static Future<List<MapIncident>> fetchForArea({
    required double lat,
    required double lng,
    required double radiusMeters,
  }) async {
    try {
      final rows = await _client.rpc('nearby_news_pins', params: {
        'center_lat': lat,
        'center_lng': lng,
        'radius_meters': radiusMeters,
        'max_results': 200,
        'max_age_days': _maxAgeDays,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map(_toMapIncident)
          .whereType<MapIncident>()
          .toList();
    } catch (_) {
      // Offline-friendly by design, same as BrazilSecurityApi.
      return [];
    }
  }

  static MapIncident? _toMapIncident(Map<String, dynamic> row) {
    final lat = (row['lat'] as num?)?.toDouble();
    final lng = (row['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final id = row['id'] as String?;
    if (id == null) return null;

    final eventType = (row['event_type'] as String?) ?? 'other';
    final severity = _mapSeverity(row['severity'] as String?);
    final city = (row['city'] as String?) ?? '';
    final state = (row['state'] as String?) ?? '';
    final occurredAt = row['occurred_at'] as String?;
    final eventCategory = row['event_category'] as String?;

    return MapIncident(
      id: 'br-news-pin-$id',
      location: LatLng(lat, lng),
      severity: severity,
      category: eventType,
      subcategory: (row['original_category'] as String?) ?? eventType,
      // Same reasoning as BrazilSecurityApi: the "in"/"em" connector is
      // locale-dependent, so the sentence is built at render time
      // (IncidentBottomSheet) from officialCity/officialState instead.
      description: '',
      dateTime:
          occurredAt != null ? DateTime.parse(occurredAt) : DateTime.now(),
      isOfficial: true,
      isApproximate: true,
      source: row['source_organisation'] as String?,
      articleUrl: row['article_url'] as String?,
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
