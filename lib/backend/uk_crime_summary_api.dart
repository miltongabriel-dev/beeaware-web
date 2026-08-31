import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One Police Force Area's aggregated crime counts (see
/// supabase/migrations/20260831140000_police_force_crime_summary_rpc.sql)
/// plus its boundary, for the UK choropleth layer — same shape as
/// MunicipalityCrimeSummary/BrazilCrimeSummaryApi, one tier coarser (43
/// England & Wales police forces instead of thousands of municipalities).
/// Only ~30 of the 43 forces ever appear here: the 13 highest crime-volume
/// forces (including Metropolitan Police/London) hit a hard, undocumented
/// result-size ceiling on data.police.uk's own `poly` query endpoint — see
/// UkPoliceAdapter's header for the full story. Those forces simply have
/// no rows to summarize, so they show no colour rather than a wrong or
/// partial count.
class PoliceForceCrimeSummary {
  final String forceName;
  final int violenceCount;
  final int propertyCount;
  final int publicSafetyCount;
  final int totalCount;

  /// One entry per polygon part — see MunicipalityCrimeSummary's own doc
  /// comment for why holes are dropped and multi-part geometry becomes
  /// several separate rings here.
  final List<List<LatLng>> polygons;

  PoliceForceCrimeSummary({
    required this.forceName,
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

class UkCrimeSummaryApi {
  static final SupabaseClient _client = Supabase.instance.client;

  // At most 43 rows ever come back — no pagination loop needed the way
  // BrazilCrimeSummaryApi's municipality-level query does.
  static Future<List<PoliceForceCrimeSummary>> fetchSummary(
      {int monthsBack = 3}) async {
    try {
      final rows = await _client.rpc('police_force_crime_summary', params: {
        'months_back': monthsBack,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map(_toSummary)
          .whereType<PoliceForceCrimeSummary>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static PoliceForceCrimeSummary? _toSummary(Map<String, dynamic> row) {
    final geometry = row['geometry'];
    if (geometry is! Map<String, dynamic>) return null;

    final polygons = _parsePolygons(geometry);
    if (polygons.isEmpty) return null;

    final forceName = row['force_name'] as String?;
    if (forceName == null) return null;

    return PoliceForceCrimeSummary(
      forceName: forceName,
      violenceCount: (row['violence_count'] as num?)?.toInt() ?? 0,
      propertyCount: (row['property_count'] as num?)?.toInt() ?? 0,
      publicSafetyCount: (row['public_safety_count'] as num?)?.toInt() ?? 0,
      totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
      polygons: polygons,
    );
  }
}
