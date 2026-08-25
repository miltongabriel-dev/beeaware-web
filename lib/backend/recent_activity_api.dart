import 'package:supabase_flutter/supabase_flutter.dart';

/// One municipality's Recent Activity signal (see
/// supabase/migrations/20260825180000_recent_activity_within_state_rpc.sql's
/// recent_activity_within_state RPC) — compares the municipality's OWN
/// last-30-days rate to its OWN trailing baseline, ranked against other
/// municipalities in the same state. A null score means there isn't
/// enough recent data for this municipality to say anything (most
/// adapters publish with a lag, so this is only populated where the
/// underlying source is genuinely current — confirmed live 2026-08-25:
/// only Belém, via PaSegupAdapter's per-occurrence recent data). Same
/// release gate as HistoricalSafety: backend-only for now, not wired
/// into any screen.
class RecentActivity {
  final String cityIbgeCode;
  final String cityName;
  final String stateCode;
  final int population;
  final int recentCount;
  final double recentRatePer100k;
  final int baselineCount;
  final double? baselineRatePer100kEquivalent;
  final double? changeRatio;
  final int? recentActivityScore;

  RecentActivity({
    required this.cityIbgeCode,
    required this.cityName,
    required this.stateCode,
    required this.population,
    required this.recentCount,
    required this.recentRatePer100k,
    required this.baselineCount,
    required this.baselineRatePer100kEquivalent,
    required this.changeRatio,
    required this.recentActivityScore,
  });
}

class RecentActivityApi {
  static final SupabaseClient _client = Supabase.instance.client;

  /// Single-municipality lookup (recent_activity_for_city RPC) — same
  /// 1000-row PostgREST cap reasoning as HistoricalSafetyApi.fetchForCity.
  static Future<RecentActivity?> fetchForCity(
    String cityIbgeCode, {
    int recentDays = 30,
    int baselineMonths = 12,
  }) async {
    try {
      final rows = await _client.rpc('recent_activity_for_city', params: {
        'target_city_ibge_code': cityIbgeCode,
        'recent_days': recentDays,
        'baseline_months': baselineMonths,
      });

      if (rows is! List || rows.isEmpty) return null;
      final row = rows.first;
      if (row is! Map<String, dynamic>) return null;
      return _toRecentActivity(row);
    } catch (_) {
      return null;
    }
  }

  static Future<List<RecentActivity>> fetchWithinStateScores({
    int recentDays = 30,
    int baselineMonths = 12,
  }) async {
    try {
      final rows =
          await _client.rpc('recent_activity_within_state', params: {
        'recent_days': recentDays,
        'baseline_months': baselineMonths,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map(_toRecentActivity)
          .whereType<RecentActivity>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static RecentActivity? _toRecentActivity(Map<String, dynamic> row) {
    final cityIbgeCode = row['city_ibge_code'] as String?;
    if (cityIbgeCode == null) return null;

    return RecentActivity(
      cityIbgeCode: cityIbgeCode,
      cityName: (row['city_name'] as String?) ?? '',
      stateCode: (row['state_code'] as String?) ?? '',
      population: (row['population'] as num?)?.toInt() ?? 0,
      recentCount: (row['recent_count'] as num?)?.toInt() ?? 0,
      recentRatePer100k:
          (row['recent_rate_per_100k'] as num?)?.toDouble() ?? 0.0,
      baselineCount: (row['baseline_count'] as num?)?.toInt() ?? 0,
      baselineRatePer100kEquivalent:
          (row['baseline_rate_per_100k_equivalent'] as num?)?.toDouble(),
      changeRatio: (row['change_ratio'] as num?)?.toDouble(),
      recentActivityScore: (row['recent_activity_score'] as num?)?.toInt(),
    );
  }
}
