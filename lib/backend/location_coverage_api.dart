import 'package:supabase_flutter/supabase_flutter.dart';

/// One row of the `location_coverage` RPC (see
/// supabase/migrations/20260823120000_location_coverage_rpc.sql) — what
/// data actually exists near a point, and how good it is. BeeAware Global
/// blueprint principle: "Never equate 'no data' with 'safe'." This is the
/// model that lets the UI say so honestly instead of showing an empty map.
class LocationCoverage {
  final String geoPrecision;
  final String eventCategory;

  /// A+/A/B/C, mirroring the blueprint's §6.2 source-grade table —
  /// EXACT/STREET police-grade data down to COUNTRY-level global baseline.
  final String grade;
  final int sourceCount;
  final DateTime? lastDataDate;
  final int? freshnessDays;

  const LocationCoverage({
    required this.geoPrecision,
    required this.eventCategory,
    required this.grade,
    required this.sourceCount,
    required this.lastDataDate,
    required this.freshnessDays,
  });

  /// Coarser than STREET/EXACT — a country-level statistic, not something
  /// tied to this specific neighbourhood. Used to drive the "limited data"
  /// empty state instead of implying full local coverage.
  bool get isCountryOnly => geoPrecision == 'COUNTRY';
}

class LocationCoverageApi {
  static final SupabaseClient _client = Supabase.instance.client;

  static Future<List<LocationCoverage>> fetchCoverage({
    required double lat,
    required double lng,
    double radiusMeters = 15000,
    String? countryCode,
  }) async {
    try {
      final rows = await _client.rpc('location_coverage', params: {
        'center_lat': lat,
        'center_lng': lng,
        'radius_meters': radiusMeters,
        'p_country_code': countryCode,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map(_toCoverage)
          .whereType<LocationCoverage>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static LocationCoverage? _toCoverage(Map<String, dynamic> row) {
    final geoPrecision = row['geo_precision'] as String?;
    final eventCategory = row['event_category'] as String?;
    final grade = row['grade'] as String?;
    if (geoPrecision == null || eventCategory == null || grade == null) {
      return null;
    }

    return LocationCoverage(
      geoPrecision: geoPrecision,
      eventCategory: eventCategory,
      grade: grade,
      sourceCount: (row['source_count'] as num?)?.toInt() ?? 0,
      lastDataDate: DateTime.tryParse((row['last_data_date'] as String?) ?? ''),
      freshnessDays: (row['freshness_days'] as num?)?.toInt(),
    );
  }
}

/// Best (lowest-letter, i.e. most precise) grade across every coverage row,
/// or null when there's no coverage at all for this area. A+ beats C the
/// same way it reads on the source-grade table — index into GRADE_ORDER,
/// lower index wins.
const List<String> _gradeOrder = ['A+', 'A', 'B', 'C', 'D', 'U'];

String? bestCoverageGrade(List<LocationCoverage> coverage) {
  if (coverage.isEmpty) return null;
  return coverage
      .map((c) => c.grade)
      .reduce((best, next) {
        final bestIdx = _gradeOrder.indexOf(best);
        final nextIdx = _gradeOrder.indexOf(next);
        if (bestIdx == -1) return next;
        if (nextIdx == -1) return best;
        return nextIdx < bestIdx ? next : best;
      });
}
