import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One French département's aggregated crime counts (see
/// supabase/migrations/20260907120000_departement_fr_crime_summary_rpc.sql)
/// plus its boundary, for the France choropleth layer — same shape as
/// MunicipioEsCrimeSummary/ConcelhoCrimeSummary. Covers all 101
/// départements (96 metropolitan incl. Corsica + 5 overseas), no
/// publication-limit gap the way Spain's municipio-level source has.
/// See FrCrimeAdapter's header for the full category-selection reasoning
/// (16 of 18 published indicators, drug-usage parent and payment fraud
/// excluded).
class DepartementFrCrimeSummary {
  final String departementName;
  final int violenceCount;
  final int propertyCount;
  final int publicSafetyCount;
  final int totalCount;

  /// One entry per polygon part — see MunicipalityCrimeSummary's own doc
  /// comment for why holes are dropped and multi-part geometry becomes
  /// several separate rings here.
  final List<List<LatLng>> polygons;

  DepartementFrCrimeSummary({
    required this.departementName,
    required this.violenceCount,
    required this.propertyCount,
    required this.publicSafetyCount,
    required this.totalCount,
    required this.polygons,
  });
}

List<LatLng> _ring(List<dynamic> ring) {
  return ring
      .map((point) => LatLng(
            (point[1] as num).toDouble(),
            (point[0] as num).toDouble(),
          ))
      .toList();
}

List<List<LatLng>> _parsePolygons(Map<String, dynamic> geometry) {
  final type = geometry['type'] as String?;
  final coordinates = geometry['coordinates'];

  if (type == 'Polygon' && coordinates is List && coordinates.isNotEmpty) {
    return [_ring(coordinates[0] as List)];
  }

  if (type == 'MultiPolygon' && coordinates is List) {
    return coordinates
        .whereType<List>()
        .where((part) => part.isNotEmpty)
        .map((part) => _ring(part[0] as List))
        .toList();
  }

  return [];
}

class FrCrimeSummaryApi {
  static final SupabaseClient _client = Supabase.instance.client;

  // At most 101 rows come back — well below PostgREST's 1000-row default
  // cap, no pagination loop needed.
  //
  // monthsBack defaults to 24, matching departement_fr_crime_summary's
  // own default: SSMSI publishes a closed annual year with real
  // publication lag (2025 data only became available in July 2026), so a
  // tighter window risks missing the only ingested year depending on
  // when this runs.
  static Future<List<DepartementFrCrimeSummary>> fetchSummary(
      {int monthsBack = 24}) async {
    try {
      final rows =
          await _client.rpc('departement_fr_crime_summary', params: {
        'months_back': monthsBack,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map(_toSummary)
          .whereType<DepartementFrCrimeSummary>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static DepartementFrCrimeSummary? _toSummary(Map<String, dynamic> row) {
    final geometry = row['geometry'];
    if (geometry is! Map<String, dynamic>) return null;

    final polygons = _parsePolygons(geometry);
    if (polygons.isEmpty) return null;

    final departementName = row['departement_name'] as String?;
    if (departementName == null) return null;

    return DepartementFrCrimeSummary(
      departementName: departementName,
      violenceCount: (row['violence_count'] as num?)?.toInt() ?? 0,
      propertyCount: (row['property_count'] as num?)?.toInt() ?? 0,
      publicSafetyCount: (row['public_safety_count'] as num?)?.toInt() ?? 0,
      totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
      polygons: polygons,
    );
  }
}
