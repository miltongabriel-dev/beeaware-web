import 'package:supabase_flutter/supabase_flutter.dart';

/// District-level crime breakdown for one point (see
/// supabase/migrations/20260826160000_district_crime_for_point_rpc.sql).
/// Generic across every state with police-district geometry (RJ's CISP,
/// SP's DP) — the RPC itself decides which area_type actually contains
/// the point, so this client never needs to know or care which state a
/// tap landed in. Null when the point isn't inside any such polygon yet
/// (most of Brazil, still — only RJ and SP have this geometry so far),
/// same "absent rather than faked" principle as the other Safety Pulse
/// dimensions.
class DistrictCrime {
  final String districtName;
  final String stateCode;
  final int violenceCount;
  final int propertyCount;
  final int publicSafetyCount;
  final int totalCount;

  DistrictCrime({
    required this.districtName,
    required this.stateCode,
    required this.violenceCount,
    required this.propertyCount,
    required this.publicSafetyCount,
    required this.totalCount,
  });
}

class DistrictCrimeApi {
  static final SupabaseClient _client = Supabase.instance.client;

  static Future<DistrictCrime?> fetch({
    required double lat,
    required double lng,
    int monthsBack = 3,
  }) async {
    try {
      final rows = await _client.rpc('district_crime_for_point', params: {
        'point_lat': lat,
        'point_lng': lng,
        'months_back': monthsBack,
      });

      if (rows is! List || rows.isEmpty) return null;
      final row = rows.first;
      if (row is! Map<String, dynamic>) return null;

      return DistrictCrime(
        districtName: row['district_name'] as String? ?? '',
        stateCode: row['state_code'] as String? ?? '',
        violenceCount: (row['violence_count'] as num?)?.toInt() ?? 0,
        propertyCount: (row['property_count'] as num?)?.toInt() ?? 0,
        publicSafetyCount: (row['public_safety_count'] as num?)?.toInt() ?? 0,
        totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
