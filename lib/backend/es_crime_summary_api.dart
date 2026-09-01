import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One Spanish municipio's aggregated crime counts (see
/// supabase/migrations/20260903120000_municipio_es_crime_summary_rpc.sql)
/// plus its boundary, for the Spain choropleth layer — same shape as
/// ConcelhoCrimeSummary/PoliceForceCrimeSummary. Covers only the 427
/// municipios with population over ~20,000 — the Ministerio del
/// Interior's own real publication limit below province level, not a
/// gap this API introduces. See EsCrimeAdapter's header for the full
/// category-selection reasoning (11 of 16 published fields, cybercrime
/// excluded).
class MunicipioEsCrimeSummary {
  final String municipioName;
  final int violenceCount;
  final int propertyCount;
  final int publicSafetyCount;
  final int totalCount;

  /// One entry per polygon part — see MunicipalityCrimeSummary's own doc
  /// comment for why holes are dropped and multi-part geometry becomes
  /// several separate rings here.
  final List<List<LatLng>> polygons;

  MunicipioEsCrimeSummary({
    required this.municipioName,
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

class EsCrimeSummaryApi {
  static final SupabaseClient _client = Supabase.instance.client;

  // At most 427 rows come back — still below PostgREST's 1000-row default
  // cap, no pagination loop needed.
  //
  // monthsBack defaults to 24, matching municipio_es_crime_summary's own
  // default: the Ministerio's balance is a year-to-date cumulative figure
  // published a few times a year, so a tighter window risks missing the
  // only ingested year depending on when this runs.
  static Future<List<MunicipioEsCrimeSummary>> fetchSummary(
      {int monthsBack = 24}) async {
    try {
      final rows = await _client.rpc('municipio_es_crime_summary', params: {
        'months_back': monthsBack,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map(_toSummary)
          .whereType<MunicipioEsCrimeSummary>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static MunicipioEsCrimeSummary? _toSummary(Map<String, dynamic> row) {
    final geometry = row['geometry'];
    if (geometry is! Map<String, dynamic>) return null;

    final polygons = _parsePolygons(geometry);
    if (polygons.isEmpty) return null;

    final municipioName = row['municipio_name'] as String?;
    if (municipioName == null) return null;

    return MunicipioEsCrimeSummary(
      municipioName: municipioName,
      violenceCount: (row['violence_count'] as num?)?.toInt() ?? 0,
      propertyCount: (row['property_count'] as num?)?.toInt() ?? 0,
      publicSafetyCount: (row['public_safety_count'] as num?)?.toInt() ?? 0,
      totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
      polygons: polygons,
    );
  }
}
