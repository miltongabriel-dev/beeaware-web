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

  // 12 months (the value this briefly used) makes the underlying
  // municipality_crime_summary RPC scan enough security_events rows to
  // blow Postgres's statement timeout — confirmed live: months_back=12
  // times out ("57014 canceling statement due to statement timeout"),
  // months_back=3 returns RJ+RS choropleth data in ~3.5s. Silently swallowed
  // by the try/catch below, so the whole choropleth (every state, not just
  // one) went dark with no visible error. Widening this again needs a
  // supporting index on security_events first, not just a bigger window.
  // This project's Supabase instance enforces a hard 1000-row ceiling per
  // response on table-returning RPCs — confirmed by hand: neither a
  // Range header nor a larger ?limit= raises it, offset=1000&limit=1000
  // does return the next 1000 rows, so the cap is per-page, not global.
  // Harmless while only RJ/RS had municipality geometry (560 rows
  // total), but backfilling the other 7 states pushed the true total
  // past 1000, and rows past the first page (São Paulo's own included)
  // went silently missing from the choropleth. Genuine pagination below
  // is the only fix; a bigger single .range() call (tried first) still
  // came back truncated at 1000.
  static const int _pageSize = 1000;

  static Future<List<MunicipalityCrimeSummary>> fetchSummary(
      {int monthsBack = 3}) async {
    try {
      final all = <MunicipalityCrimeSummary>[];
      var offset = 0;
      // Bounded by Brazil's real municipality count (5570) rather than
      // an unconditional while(true) — a hard ceiling on iterations, not
      // just a nicety, in case the server ever misbehaves and keeps
      // returning full pages past the true end.
      while (offset < 5570) {
        final rows = await _client
            .rpc('municipality_crime_summary', params: {
              'months_back': monthsBack,
            })
            .range(offset, offset + _pageSize - 1);

        if (rows is! List) break;

        all.addAll(rows
            .whereType<Map<String, dynamic>>()
            .map(_toSummary)
            .whereType<MunicipalityCrimeSummary>());

        if (rows.length < _pageSize) break; // last page
        offset += _pageSize;
      }
      return all;
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
