import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import 'map_incident.dart';
import 'incident_persistence.dart';
import '../backend/incident_api.dart';
import '../backend/uk_police_api.dart';

class IncidentStore {
  static List<MapIncident> _incidents = [];

  static final StreamController<List<MapIncident>> _controller =
      StreamController<List<MapIncident>>.broadcast();

  /// Stream that always emits current state first
  static Stream<List<MapIncident>> get stream {
    return _controller.stream.startWith(
      List.unmodifiable(_incidents),
    );
  }

  static List<MapIncident> get incidents => List.unmodifiable(_incidents);

  /// 🚀 inicializa store (local + community)
  static Future<void> init() async {
    // 1️⃣ cache local (community only)
    _incidents = await IncidentPersistence.load();
    _emit();

    // 2️⃣ community (Supabase)
    await syncFromBackend();
  }

  /// 🔄 sincroniza incidentes visíveis do Supabase (community)
  static Future<void> syncFromBackend() async {
    try {
      final remote = await IncidentApi.fetchVisibleIncidents();
      bool changed = false;

      for (final r in remote) {
        final exists = _incidents.any((i) => i.id == r.id);
        if (!exists) {
          _incidents = [..._incidents, r];
          changed = true;
        }
      }

      if (changed) {
        _emit();
        await IncidentPersistence.save(_incidents);
      }
    } catch (_) {
      // offline-friendly por design
    }
  }

  /// 🏛️ sincroniza incidentes oficiais para a área visível do mapa
  static final Set<String> _fetchedCells = {};

  static Future<void> syncOfficialForBounds(LatLngBounds bounds) async {
    try {
      final centerLat = (bounds.north + bounds.south) / 2;
      final centerLng = (bounds.east + bounds.west) / 2;

      final distance = const Distance();
      final radius = distance.as(
            LengthUnit.Meter,
            LatLng(bounds.north, bounds.east),
            LatLng(bounds.south, bounds.west),
          ) /
          2;

      // 🔑 chave de cache por célula (~100m)
      final key =
          '${centerLat.toStringAsFixed(3)}_${centerLng.toStringAsFixed(3)}';

      if (_fetchedCells.contains(key)) return;

      _fetchedCells.add(key);

      // evita crescimento infinito
      if (_fetchedCells.length > 50) {
        _fetchedCells.clear();
      }

      final official = await UkPoliceApi.fetchForArea(
        lat: centerLat,
        lng: centerLng,
        radiusMeters: radius.clamp(500, 5000),
      );

      bool changed = false;

      for (final o in official) {
        final exists = _incidents.any((i) => i.id == o.id);
        if (!exists) {
          _incidents = [..._incidents, o];
          changed = true;
        }
      }

      if (changed) {
        _emit();
      }
    } catch (_) {
      // silencioso por design
    }
  }

  /// ➕ adiciona incidente local (community)
  static Future<void> addWithDelay(
    MapIncident incident,
    Duration delay,
  ) async {
    final now = DateTime.now();

    final pending = MapIncident(
      id: incident.id,
      location: incident.location,
      severity: incident.severity,
      category: incident.category,
      subcategory: incident.subcategory,
      description: incident.description,
      dateTime: incident.dateTime,
      isPending: true,
      visibleAt: now.add(delay),
      hash: incident.hash,
      isOfficial: false,
    );

    _incidents = [..._incidents, pending];
    _emit();
    await IncidentPersistence.save(_incidents);

    Future.delayed(delay, () async {
      await syncFromBackend();
    });
  }

  /// 🧹 Helper para dev/testing
  static Future<void> clear() async {
    _incidents = [];
    _emit();
    await IncidentPersistence.save(_incidents);
  }

  static void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_incidents));
    }
  }

  static void dispose() {
    _controller.close();
  }
}

/// Lightweight Stream extension
extension _StartWith<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
