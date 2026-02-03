import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'map_incident.dart';

class IncidentPersistence {
  static const _key = 'aware_incidents_v1'; // 👈 versionado

  /// 💾 Salva apenas incidentes válidos
  static Future<void> save(List<MapIncident> incidents) async {
    final prefs = await SharedPreferences.getInstance();

    final now = DateTime.now();

    // 🔒 regra: não persistir lixo local
    final safeIncidents = incidents.where((i) {
      // ignora incidentes com data inválida
      if (i.dateTime.isAfter(now.add(const Duration(minutes: 5)))) {
        return false;
      }

      // ignora incidentes que ainda não deveriam existir
      if (i.visibleAt != null && i.visibleAt!.isAfter(now)) {
        return false;
      }

      return true;
    }).toList();

    final jsonList = safeIncidents.map((i) => i.toJson()).toList();
    await prefs.setString(_key, jsonEncode(jsonList));
  }

  /// 📥 Carrega apenas dados coerentes
  static Future<List<MapIncident>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) return [];

      final now = DateTime.now();

      return decoded
          .whereType<Map>()
          .map(
            (e) => MapIncident.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .where((i) {
        // 🧹 limpeza defensiva
        if (i.visibleAt != null && i.visibleAt!.isAfter(now)) {
          return false;
        }
        return true;
      }).toList();
    } catch (_) {
      // 🧯 nunca quebrar o app por cache corrompido
      return [];
    }
  }

  /// 🧨 utilitário (debug / reset total)
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
