import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One candidate route (roadmap 9.5/11.12) — geometry from the
/// route-awareness Edge Function (proxies OpenRouteService, see its own
/// header for why a second route needs a waypoint-detour trick for
/// pedestrian routing), signal counts from the route_safety_signals RPC
/// (250-500m buffer, see its own header). Deliberately no "safety score"
/// field — roadmap 13.3's naming rule ("avoid 'Safest Route'") is
/// easiest to honour by never computing a rankable number in the first
/// place, only exposing the raw counts HomeScreen's route panel compares.
class RouteOption {
  final String id;
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final int officialSignalCount;
  final int officialHighSeverityCount;
  final int communitySignalCount;
  final int totalSignalCount;

  RouteOption({
    required this.id,
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.officialSignalCount,
    required this.officialHighSeverityCount,
    required this.communitySignalCount,
    required this.totalSignalCount,
  });
}

class RouteAwarenessApi {
  static final SupabaseClient _client = Supabase.instance.client;

  /// Fetches route geometry (1-2 routes) then, for each, counts nearby
  /// safety signals — two separate calls per route rather than one
  /// combined RPC, since routing (external API) and signal-counting
  /// (internal PostGIS) are genuinely different concerns with different
  /// failure modes; a routing outage shouldn't be indistinguishable from
  /// a signal-counting bug.
  static Future<List<RouteOption>> fetchRoutes({
    required LatLng origin,
    required LatLng destination,
    double bufferMeters = 300,
    int windowDays = 90,
  }) async {
    final response = await _client.functions.invoke(
      'route-awareness',
      body: {
        'origin': {'lat': origin.latitude, 'lng': origin.longitude},
        'destination': {
          'lat': destination.latitude,
          'lng': destination.longitude
        },
      },
    );

    final data = response.data;
    if (data is! Map || data['routes'] is! List) return [];

    final routes = <RouteOption>[];
    for (final raw in (data['routes'] as List)) {
      if (raw is! Map) continue;
      final geometry = raw['geometry'];
      if (geometry is! Map || geometry['coordinates'] is! List) continue;

      final points = (geometry['coordinates'] as List)
          .whereType<List>()
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      if (points.isEmpty) continue;

      final signals = await _fetchSignals(
        geometry: geometry as Map<String, dynamic>,
        bufferMeters: bufferMeters,
        windowDays: windowDays,
      );

      routes.add(RouteOption(
        id: (raw['id'] as String?) ?? 'A',
        points: points,
        distanceMeters: (raw['distanceMeters'] as num?)?.toDouble() ?? 0,
        durationSeconds: (raw['durationSeconds'] as num?)?.toDouble() ?? 0,
        officialSignalCount: signals?.$1 ?? 0,
        officialHighSeverityCount: signals?.$2 ?? 0,
        communitySignalCount: signals?.$3 ?? 0,
        totalSignalCount: signals?.$4 ?? 0,
      ));
    }

    return routes;
  }

  static Future<(int, int, int, int)?> _fetchSignals({
    required Map<String, dynamic> geometry,
    required double bufferMeters,
    required int windowDays,
  }) async {
    try {
      final rows = await _client.rpc('route_safety_signals', params: {
        'route_geometry': geometry,
        'buffer_meters': bufferMeters,
        'window_days': windowDays,
      });

      if (rows is! List || rows.isEmpty) return null;
      final row = rows.first;
      if (row is! Map<String, dynamic>) return null;

      return (
        (row['official_count'] as num?)?.toInt() ?? 0,
        (row['official_high_severity_count'] as num?)?.toInt() ?? 0,
        (row['community_count'] as num?)?.toInt() ?? 0,
        (row['total_count'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
