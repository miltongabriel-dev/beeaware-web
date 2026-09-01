import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One Northern Ireland council's ("Local Government District", area_type
/// 'LGD') aggregated crime counts (see
/// supabase/migrations/20260905180000_lgd_crime_summary_rpc.sql) plus its
/// boundary, for the Northern Ireland choropleth layer — same shape as
/// PoliceForceCrimeSummary, just 11 councils instead of 43 England &
/// Wales police forces. Unlike that source, every one of the 11 councils
/// was verified live to succeed (a whole-country `poly` query 503s at
/// that size, but no single council does — see NiPoliceAdapter's own
/// header), so there's no equivalent "some areas simply have no data"
/// caveat here.
class LgdCrimeSummary {
  final String lgdName;
  final int violenceCount;
  final int propertyCount;
  final int publicSafetyCount;
  final int totalCount;

  /// One entry per polygon part — see PoliceForceCrimeSummary's own doc
  /// comment for why holes are dropped and multi-part geometry becomes
  /// several separate rings here.
  final List<List<LatLng>> polygons;

  LgdCrimeSummary({
    required this.lgdName,
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

class NiCrimeSummaryApi {
  static final SupabaseClient _client = Supabase.instance.client;

  // At most 11 rows ever come back — no pagination needed.
  //
  // monthsBack defaults to 6, same window as police_force_crime_summary
  // for the same reason (a live monthly source with real reporting lag —
  // see 20260904110000's own header): NiPoliceAdapter only ever holds a
  // single latest month, refreshed by a weekly cron.
  static Future<List<LgdCrimeSummary>> fetchSummary({int monthsBack = 6}) async {
    try {
      final rows = await _client.rpc('lgd_crime_summary', params: {
        'months_back': monthsBack,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map(_toSummary)
          .whereType<LgdCrimeSummary>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static LgdCrimeSummary? _toSummary(Map<String, dynamic> row) {
    final geometry = row['geometry'];
    if (geometry is! Map<String, dynamic>) return null;

    final polygons = _parsePolygons(geometry);
    if (polygons.isEmpty) return null;

    final lgdName = row['lgd_name'] as String?;
    if (lgdName == null) return null;

    return LgdCrimeSummary(
      lgdName: lgdName,
      violenceCount: (row['violence_count'] as num?)?.toInt() ?? 0,
      propertyCount: (row['property_count'] as num?)?.toInt() ?? 0,
      publicSafetyCount: (row['public_safety_count'] as num?)?.toInt() ?? 0,
      totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
      polygons: polygons,
    );
  }
}
