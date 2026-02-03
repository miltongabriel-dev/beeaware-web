import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../map/map_incident.dart';

class UkPoliceApi {
  /// Crimes próximos a um ponto (lat/lng).
  /// Nota: o endpoint não aceita radius; então filtramos localmente por distância.
  static Future<List<MapIncident>> fetchForArea({
    required double lat,
    required double lng,
    required double radiusMeters,
  }) async {
    final url = 'https://data.police.uk/api/crimes-street/all-crime'
        '?lat=$lat&lng=$lng';

    final res = await http.get(Uri.parse(url));

    if (res.statusCode != 200) {
      throw Exception('Failed to fetch police data (${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! List) return [];

    final center = LatLng(lat, lng);
    final distance = const Distance();

    final List<MapIncident> out = [];

    for (final row in decoded) {
      if (row is! Map) continue;

      final categoryRaw = row['category'] as String?;
      final category = (categoryRaw == null || categoryRaw.trim().isEmpty)
          ? 'unknown'
          : categoryRaw;

      final loc = row['location'];
      if (loc is! Map) continue;

      final latStr = loc['latitude']?.toString();
      final lngStr = loc['longitude']?.toString();
      if (latStr == null || lngStr == null) continue;

      final crimeLat = double.tryParse(latStr);
      final crimeLng = double.tryParse(lngStr);
      if (crimeLat == null || crimeLng == null) continue;

      final point = LatLng(crimeLat, crimeLng);

      // ✅ filtro por raio local
      final meters = distance.as(LengthUnit.Meter, center, point);
      if (meters > radiusMeters) continue;

      final monthStr = row['month']?.toString(); // "YYYY-MM"
      final dateTime = _parsePoliceMonth(monthStr);

      out.add(
        MapIncident(
          id: 'uk-${row['id'] ?? '${crimeLat}_${crimeLng}_${monthStr ?? 'na'}'}',
          location: point,
          severity: _mapSeverity(category),
          category: 'Police report',
          subcategory: category.replaceAll('-', ' '),
          description: 'Reported by UK Police (${monthStr ?? _ymNow()})',
          dateTime: dateTime,
          isOfficial: true,
        ),
      );
    }

    return out;
  }

  /// ⚖️ Regra conservadora de severidade (não sensacionalista)
  static IncidentSeverity _mapSeverity(String category) {
    switch (category) {
      case 'violent-crime':
      case 'robbery':
      case 'sexual-offences':
      case 'possession-of-weapons':
        return IncidentSeverity.high;

      case 'burglary':
      case 'vehicle-crime':
      case 'drugs':
        return IncidentSeverity.medium;

      default:
        return IncidentSeverity.low;
    }
  }

  static DateTime _parsePoliceMonth(String? ym) {
    // esperado: "YYYY-MM"
    if (ym == null || ym.length < 7) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, 1);
    }

    final parts = ym.split('-');
    if (parts.length != 2) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, 1);
    }

    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);

    if (y == null || m == null || m < 1 || m > 12) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, 1);
    }

    return DateTime(y, m, 1);
  }

  static String _ymNow() {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    return '${now.year}-$mm';
  }
}
