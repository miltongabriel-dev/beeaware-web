import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One municipality's aggregated crime counts (see
/// supabase/migrations/20260821180000_rj_isp_and_choropleth.sql's
/// municipality_crime_summary RPC) plus its boundary, ready for a
/// choropleth layer. There is no point-level violence data anywhere —
/// individual crime records with addresses aren't published, for victim
/// safety — so this is the only honest way to surface it: colour the
/// area, not a pin.
class MunicipalityCrimeSummary {
  final String cityIbgeCode;
  final String cityName;
  final String stateCode;
  final int violenceCount;
  final int propertyCount;
  final int publicSafetyCount;
  final int totalCount;

  /// One entry per polygon part — plain Polygon geometry has exactly one,
  /// MultiPolygon (common for municipalities with islands/exclaves) has
  /// several. Holes are ignored: municipality boundaries at the "minima"
  /// quality IBGE serves rarely have meaningful ones, and a full hole
  /// render isn't worth the added complexity for a coarse choropleth.
  final List<List<LatLng>> polygons;

  MunicipalityCrimeSummary({
    required this.cityIbgeCode,
    required this.cityName,
    required this.stateCode,
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

class BrazilCrimeSummaryApi {
  static final SupabaseClient _client = Supabase.instance.client;

  static Future<List<MunicipalityCrimeSummary>> fetchSummary(
      {int monthsBack = 12}) async {
    try {
      final rows = await _client.rpc('municipality_crime_summary', params: {
        'months_back': monthsBack,
      });

      if (rows is! List) return [];

      return rows
          .whereType<Map<String, dynamic>>()
          .map(_toSummary)
          .whereType<MunicipalityCrimeSummary>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static MunicipalityCrimeSummary? _toSummary(Map<String, dynamic> row) {
    final geometry = row['geometry'];
    if (geometry is! Map<String, dynamic>) return null;

    final polygons = _parsePolygons(geometry);
    if (polygons.isEmpty) return null;

    final cityIbgeCode = row['city_ibge_code'] as String?;
    if (cityIbgeCode == null) return null;

    return MunicipalityCrimeSummary(
      cityIbgeCode: cityIbgeCode,
      cityName: (row['city_name'] as String?) ?? '',
      stateCode: (row['state_code'] as String?) ?? '',
      violenceCount: (row['violence_count'] as num?)?.toInt() ?? 0,
      propertyCount: (row['property_count'] as num?)?.toInt() ?? 0,
      publicSafetyCount: (row['public_safety_count'] as num?)?.toInt() ?? 0,
      totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
      polygons: polygons,
    );
  }
}
