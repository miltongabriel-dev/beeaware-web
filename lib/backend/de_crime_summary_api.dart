import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One German Bundesland's aggregated crime counts (see
/// supabase/migrations/20260908120000_bundesland_de_crime_summary_rpc.sql)
/// plus its boundary, for the Germany choropleth layer — same shape as
/// DepartementFrCrimeSummary/MunicipioEsCrimeSummary. Covers all 16
/// Bundesländer. See DeCrimeAdapter's header for the full category-
/// selection reasoning (leaf Schlüssel codes only; residence/asylum-law
/// violations and cybercrime excluded, no physical-safety bucket).
class BundeslandDeCrimeSummary {
  final String bundeslandName;
  final int violenceCount;
  final int propertyCount;
  final int publicSafetyCount;
  final int totalCount;

  /// One entry per polygon part — see MunicipalityCrimeSummary's own doc
  /// comment for why holes are dropped and multi-part geometry becomes
  /// several separate rings here.
  final List<List<LatLng>> polygons;

  BundeslandDeCrimeSummary({
    required this.bundeslandName,
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

class DeCrimeSummaryApi {
  static final SupabaseClient _client = Supabase.instance.client;

  // At most 16 rows come back — well below PostgREST's 1000-row default
  // cap, no pagination loop needed.
  //
  // monthsBack defaults to 24, matching bundesland_de_crime_summary's
  // own default: BKA publishes a closed annual year with real
  // publication lag (2025 data only became available in March 2026), so
  // a tighter window risks missing the only ingested year depending on
  // when this runs.
  static Future<List<BundeslandDeCrimeSummary>> fetchSummary(
      {int monthsBack = 24}) async {
    try {
      final rows =
          await _client.rpc('bundesland_de_crime_summary', params: {
        'months_back': monthsBack,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map(_toSummary)
          .whereType<BundeslandDeCrimeSummary>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static BundeslandDeCrimeSummary? _toSummary(Map<String, dynamic> row) {
    final geometry = row['geometry'];
    if (geometry is! Map<String, dynamic>) return null;

    final polygons = _parsePolygons(geometry);
    if (polygons.isEmpty) return null;

    final bundeslandName = row['bundesland_name'] as String?;
    if (bundeslandName == null) return null;

    return BundeslandDeCrimeSummary(
      bundeslandName: bundeslandName,
      violenceCount: (row['violence_count'] as num?)?.toInt() ?? 0,
      propertyCount: (row['property_count'] as num?)?.toInt() ?? 0,
      publicSafetyCount: (row['public_safety_count'] as num?)?.toInt() ?? 0,
      totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
      polygons: polygons,
    );
  }
}
