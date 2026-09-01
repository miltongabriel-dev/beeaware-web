import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One Portuguese concelho's aggregated crime counts (see
/// supabase/migrations/20260902120000_concelho_crime_summary_rpc.sql)
/// plus its boundary, for the Portugal choropleth layer — same shape as
/// PoliceForceCrimeSummary/MunicipalityCrimeSummary, at concelho
/// granularity (308 municipalities, same order of magnitude as Brazil's
/// municipality tier, finer than the UK's ~43 police forces). Built from
/// DGPJ's only 8 mutually-exclusive "crimes específicos" categories, not
/// total registered crime — see PtCrimeAdapter's header for why.
class ConcelhoCrimeSummary {
  final String concelhoName;
  final int violenceCount;
  final int propertyCount;
  final int publicSafetyCount;
  final int totalCount;

  /// One entry per polygon part — see MunicipalityCrimeSummary's own doc
  /// comment for why holes are dropped and multi-part geometry becomes
  /// several separate rings here.
  final List<List<LatLng>> polygons;

  ConcelhoCrimeSummary({
    required this.concelhoName,
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

class PtCrimeSummaryApi {
  static final SupabaseClient _client = Supabase.instance.client;

  // At most 308 rows come back — still below PostgREST's 1000-row default
  // cap, no pagination loop needed the way BrazilCrimeSummaryApi's
  // municipality-level query does.
  //
  // monthsBack defaults to 24, matching concelho_crime_summary's own
  // default: DGPJ only publishes annually and with a lag, so a tighter
  // window risks missing the only ingested year depending on the time of
  // year this runs.
  static Future<List<ConcelhoCrimeSummary>> fetchSummary(
      {int monthsBack = 24}) async {
    try {
      final rows = await _client.rpc('concelho_crime_summary', params: {
        'months_back': monthsBack,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map(_toSummary)
          .whereType<ConcelhoCrimeSummary>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static ConcelhoCrimeSummary? _toSummary(Map<String, dynamic> row) {
    final geometry = row['geometry'];
    if (geometry is! Map<String, dynamic>) return null;

    final polygons = _parsePolygons(geometry);
    if (polygons.isEmpty) return null;

    final concelhoName = row['concelho_name'] as String?;
    if (concelhoName == null) return null;

    return ConcelhoCrimeSummary(
      concelhoName: concelhoName,
      violenceCount: (row['violence_count'] as num?)?.toInt() ?? 0,
      propertyCount: (row['property_count'] as num?)?.toInt() ?? 0,
      publicSafetyCount: (row['public_safety_count'] as num?)?.toInt() ?? 0,
      totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
      polygons: polygons,
    );
  }
}
