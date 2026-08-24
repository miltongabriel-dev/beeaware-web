import 'package:supabase_flutter/supabase_flutter.dart';

/// One municipality's NATIONAL Historical Safety score (see
/// supabase/migrations/20260824220000_historical_safety_homicide_only.sql's
/// historical_safety RPC) — a relative percentile ranking, NOT an
/// absolute probability of safety. Homicide-only on purpose: validating
/// the first version (which pooled every VIOLENCE/PROPERTY/PUBLIC_SAFETY
/// category) against real capitals showed it comparing states whose
/// adapters report very different scopes as if they were equivalent —
/// RJ-ISP reports comprehensively, AL-SEDS reports only lethal violent
/// crime, so pooling categories made Rio look far more dangerous than
/// Belo Horizonte purely from reporting breadth, not real safety.
/// Homicide is the one event_type every state with any crime data
/// actually reports, confirmed via event_type_coverage() — see the
/// migration's own header for the full story. Backend-only for now: the
/// roadmap's own release gate ("do not release a user-facing score until
/// normalisation, coverage bias and source freshness have been
/// validated") means this isn't wired into any screen yet.
class HistoricalSafety {
  final String cityIbgeCode;
  final String cityName;
  final String stateCode;
  final int population;
  final double homicideRatePer100k;
  final int score;
  final int totalCount;

  HistoricalSafety({
    required this.cityIbgeCode,
    required this.cityName,
    required this.stateCode,
    required this.population,
    required this.homicideRatePer100k,
    required this.score,
    required this.totalCount,
  });
}

/// One municipality's WITHIN-STATE Historical Safety score (see
/// historical_safety_within_state RPC,
/// supabase/migrations/20260824230000_historical_safety_within_state_rpc.sql)
/// — the broader severity-weighted VIOLENCE+PROPERTY+PUBLIC_SAFETY view,
/// but ranked only against other municipalities in the SAME state rather
/// than nationally. Every municipality in one state shares the same
/// adapter's reporting scope, so this comparison is apples-to-apples in
/// a way the national homicide-only score and the broader category set
/// can't be combined into one number. A complementary lens, not a
/// replacement for HistoricalSafety above.
class HistoricalSafetyWithinState {
  final String cityIbgeCode;
  final String cityName;
  final String stateCode;
  final int population;
  final double weightedRatePer100k;
  final int score;
  final int totalCount;

  HistoricalSafetyWithinState({
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

  static Future<List<HistoricalSafety>> fetchNationalScores(
      {int monthsBack = 12}) async {
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

  static Future<List<HistoricalSafetyWithinState>> fetchWithinStateScores(
      {int monthsBack = 12}) async {
    try {
      final rows =
          await _client.rpc('historical_safety_within_state', params: {
        'months_back': monthsBack,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map(_toHistoricalSafetyWithinState)
          .whereType<HistoricalSafetyWithinState>()
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
      homicideRatePer100k:
          (row['homicide_rate_per_100k'] as num?)?.toDouble() ?? 0.0,
      score: score,
      totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
    );
  }

  static HistoricalSafetyWithinState? _toHistoricalSafetyWithinState(
      Map<String, dynamic> row) {
    final cityIbgeCode = row['city_ibge_code'] as String?;
    if (cityIbgeCode == null) return null;

    final score = (row['historical_safety_score'] as num?)?.toInt();
    if (score == null) return null;

    return HistoricalSafetyWithinState(
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
