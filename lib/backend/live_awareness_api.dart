import 'package:supabase_flutter/supabase_flutter.dart';

/// Live Awareness for one point (see
/// supabase/migrations/20260825190000_live_awareness_rpc.sql's
/// live_awareness RPC) — the third Safety Pulse dimension (roadmap 1.2),
/// a raw recent-signal count near a coordinate, not a 0-100 score.
/// Deliberately not scored: at a 24h/72h window even the busiest
/// municipality BeeAware covers today only sees a handful of events, so
/// ranking that would manufacture precision the data doesn't have — see
/// the migration's own header. Combines official EXACT/STREET events
/// (the same ones nearby_security_events shows as map pins) with visible
/// community reports; news and 190 calls aren't built yet, so they're
/// simply absent rather than faked. Same release gate as HistoricalSafety
/// and RecentActivity: backend + Dart client only, not wired into any
/// screen yet.
class LiveAwareness {
  final int officialCount;
  final int officialHighSeverityCount;
  final int communityCount;
  final int totalCount;

  LiveAwareness({
    required this.officialCount,
    required this.officialHighSeverityCount,
    required this.communityCount,
    required this.totalCount,
  });
}

class LiveAwarenessApi {
  static final SupabaseClient _client = Supabase.instance.client;

  static Future<LiveAwareness?> fetch({
    required double lat,
    required double lng,
    double radiusMeters = 2000,
    int windowHours = 24,
  }) async {
    try {
      final rows = await _client.rpc('live_awareness', params: {
        'center_lat': lat,
        'center_lng': lng,
        'radius_meters': radiusMeters,
        'window_hours': windowHours,
      });

      if (rows is! List || rows.isEmpty) return null;
      final row = rows.first;
      if (row is! Map<String, dynamic>) return null;

      return LiveAwareness(
        officialCount: (row['official_count'] as num?)?.toInt() ?? 0,
        officialHighSeverityCount:
            (row['official_high_severity_count'] as num?)?.toInt() ?? 0,
        communityCount: (row['community_count'] as num?)?.toInt() ?? 0,
        totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
