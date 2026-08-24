import 'package:supabase_flutter/supabase_flutter.dart';

/// One municipality's Historical Safety score (see
/// supabase/migrations/20260824190000_historical_safety_rpc.sql's
/// historical_safety RPC) — a relative, population-normalized,
/// severity-weighted ranking, NOT an absolute probability of safety.
/// Backend-only for now: the roadmap's own release gate ("do not release
/// a user-facing score until normalisation, coverage bias and source
/// freshness have been validated in the first three pilot markets")
/// means this isn't wired into any screen yet — see the RPC's own header
/// for why the score is a percentile rank, not an absolute number.
class HistoricalSafety {
  final String cityIbgeCode;
  final String cityName;
  final String stateCode;
  final int population;
  final double weightedRatePer100k;
  final int score;
  final int totalCount;

  HistoricalSafety({
    required this.cityIbgeCode,
    required this.cityName,
    required this.stateCode,
    required this.population,
    required this.weightedRatePer100k,
    required this.score,
    required this.totalCount,
  });
}

class HistoricalSafetyApi {
  static final SupabaseClient _client = Supabase.instance.client;

  static Future<List<HistoricalSafety>> fetchScores({int monthsBack = 12}) async {
    try {
      final rows = await _client.rpc('historical_safety', params: {
        'months_back': monthsBack,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map(_toHistoricalSafety)
          .whereType<HistoricalSafety>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static HistoricalSafety? _toHistoricalSafety(Map<String, dynamic> row) {
    final cityIbgeCode = row['city_ibge_code'] as String?;
    if (cityIbgeCode == null) return null;

    final score = (row['historical_safety_score'] as num?)?.toInt();
    if (score == null) return null;

    return HistoricalSafety(
      cityIbgeCode: cityIbgeCode,
      cityName: (row['city_name'] as String?) ?? '',
      stateCode: (row['state_code'] as String?) ?? '',
      population: (row['population'] as num?)?.toInt() ?? 0,
      weightedRatePer100k:
          (row['weighted_rate_per_100k'] as num?)?.toDouble() ?? 0.0,
      score: score,
      totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
    );
  }
}
