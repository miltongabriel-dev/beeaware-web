import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';
import '../map/map_incident.dart';

class UkPoliceApi {
  static Future<List<MapIncident>> fetchForArea({
    required double lat,
    required double lng,
    required double radiusMeters,
  }) async {
    final List<MapIncident> allIncidents = [];
    final distance = const Distance();
    final center = LatLng(lat, lng);

    // 📅 Buscamos os últimos 4 meses para garantir que pegamos os disponíveis
    final List<String> monthsToFetch = _getLastMonths(4);

    for (String month in monthsToFetch) {
      try {
        final url = 'https://data.police.uk/api/crimes-street/all-crime'
            '?lat=$lat&lng=$lng&date=$month';

        final res = await http.get(Uri.parse(url));

        // ✅ PROTEÇÃO: Se der 404 (mês ainda não existe), apenas pula para o próximo
        if (res.statusCode != 200) {
          debugPrint('ℹ️ BeeAware: Mês $month ainda não disponível (404).');
          continue;
        }

        final decoded = jsonDecode(res.body);
        if (decoded is! List) continue;

        debugPrint('✅ BeeAware: Carregados ${decoded.length} itens de $month');

        for (final row in decoded) {
          if (row is! Map) continue;

          final loc = row['location'];
          if (loc is! Map) continue; // Garante que existe localização

          final latStr = loc['latitude']?.toString();
          final lngStr = loc['longitude']?.toString();
          if (latStr == null || lngStr == null) continue;

          final crimeLat = double.tryParse(latStr);
          final crimeLng = double.tryParse(lngStr);
          if (crimeLat == null || crimeLng == null) continue;

          final point = LatLng(crimeLat, crimeLng);

          // Pega o nome da rua para a descrição
          String streetName = "Location not specified";
          if (loc['street'] is Map) {
            streetName = loc['street']['name'] ?? "Location not specified";
          }

          // Filtro de raio
          final meters = distance.as(LengthUnit.Meter, center, point);
          if (meters > radiusMeters) continue;

          final category = (row['category'] as String?) ?? 'unknown';

          allIncidents.add(
            MapIncident(
              id: 'uk-${row['id'] ?? '${crimeLat}_${crimeLng}_$month'}',
              location: point,
              severity: _mapSeverity(category),
              category: 'Police report',
              subcategory: category.replaceAll('-', ' '),
              // Aqui a descrição fica muito mais rica e profissional:
              description: 'Police reported ${category.replaceAll('-', ' ')} '
                  'on or near $streetName. '
                  'Reported in $month.',
              dateTime: _parsePoliceMonth(month),
              isOfficial: true,
              source: 'UK Police',
            ),
          );
        }
      } catch (e) {
        debugPrint('⚠️ Erro ao processar mês $month: $e');
        // O erro 'Cannot read properties of undefined' acontecia aqui por falta de tratamento
      }
    }
    return allIncidents;
  }

  static List<String> _getLastMonths(int count) {
    final List<String> months = [];
    final now = DateTime.now();
    for (int i = 0; i < count; i++) {
      // Começamos a contar de 1 mês atrás, pois o mês atual NUNCA está disponível
      final date = DateTime(now.year, now.month - (i + 1), 1);
      final monthStr = date.month.toString().padLeft(2, '0');
      months.add('${date.year}-$monthStr');
    }
    return months;
  }

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

  static DateTime _parsePoliceMonth(String ym) {
    try {
      final parts = ym.split('-');
      return DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
    } catch (_) {
      return DateTime.now();
    }
  }
}
