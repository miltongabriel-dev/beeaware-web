import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../map/map_incident.dart';

class IncidentApi {
  static final SupabaseClient _client = Supabase.instance.client;
  static const String _table = 'incidents';

  // ⏱️ cooldown local (anti-spam leve)
  static DateTime? _lastSubmit;

  static bool canSubmit() {
    if (_lastSubmit == null) return true;
    return DateTime.now().difference(_lastSubmit!) > const Duration(minutes: 2);
  }

  static String _generateAnonymousHash() {
    final seed = DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(999999).toString();
    return sha256.convert(utf8.encode(seed)).toString();
  }

  /// 🚨 cria incidente (pronto para sync entre devices)
  static Future<void> createIncident(MapIncident incident) async {
    if (!canSubmit()) {
      throw Exception('Aguarde um pouco antes de reportar novamente.');
    }

    // Usamos .toUtc() para garantir que todos os telemóveis falem a mesma língua
    final now = DateTime.now().toUtc();

    final data = {
      'lat': incident.location.latitude,
      'lng': incident.location.longitude,
      'category': incident.category,
      'subcategory': incident.subcategory,
      'severity': incident.severity.name,
      'description': incident.description,
      'hash_fingerprint': incident.hash ?? _generateAnonymousHash(),
      'status': 'visible',
      'visible_at': now.toIso8601String(), // Hora exata do envio
      'created_at': now.toIso8601String(),
    };

    await _client.from(_table).insert(data);
    _lastSubmit = DateTime.now();
  }

  /// 🔍 busca incidentes já visíveis (cross-device)
  ///
  /// Scoped to the last ~2 months — the map is meant to show recent,
  /// actionable reports, not the full history (older data is still used
  /// for the regional trend charts, via separate longer-window queries).
  static Future<List<MapIncident>> fetchVisibleIncidents() async {
    try {
      final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 60));
      final res = await _client
          .from(_table)
          .select()
          .eq('status', 'visible')
          .gte('created_at', cutoff.toIso8601String())
          .order('created_at', ascending: false);

      return (res as List)
          .map<MapIncident>(
            (e) => MapIncident.fromSupabase(e as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      print('Erro na persistência: $e');
      return [];
    }
  }
}
