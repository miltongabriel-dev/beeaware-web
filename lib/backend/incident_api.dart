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
      throw Exception('Please wait before submitting another report.');
    }

    final now = DateTime.now();
    final visibleAt = incident.visibleAt ?? now.add(const Duration(minutes: 1));

    final hash = incident.hash ?? _generateAnonymousHash();

    final data = {
      'lat': incident.location.latitude,
      'lng': incident.location.longitude,
      'category': incident.category,
      'subcategory': incident.subcategory,
      'severity': incident.severity.name,
      'description': incident.description,
      'hash_fingerprint': hash,

      // 🔑 regra clara de visibilidade
      'status': visibleAt.isAfter(now) ? 'pending' : 'visible',
      'visible_at': visibleAt.toIso8601String(),
      'created_at': now.toIso8601String(),
    };

    await _client.from(_table).insert(data);

    _lastSubmit = now;
  }

  /// 🔍 busca incidentes já visíveis (cross-device)
  static Future<List<MapIncident>> fetchVisibleIncidents() async {
    final res = await _client
        .from(_table)
        .select()
        .eq('status', 'visible')
        .lte(
          'visible_at',
          DateTime.now().toIso8601String(),
        )
        .order('created_at', ascending: false);

    return (res as List)
        .map<MapIncident>(
          (e) => MapIncident.fromSupabase(e as Map<String, dynamic>),
        )
        .toList();
  }
}
