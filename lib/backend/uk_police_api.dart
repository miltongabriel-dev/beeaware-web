import 'dart:convert';
import 'dart:ui' show PlatformDispatcher, Locale;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';
import '../l10n/app_localizations.dart';
import '../map/map_incident.dart';

/// Loads the strings for the device's current locale without needing a
/// BuildContext — this runs in the data layer (IncidentStore), outside
/// the widget tree. Falls back to Portuguese for anything but English,
/// mirroring MaterialApp's supportedLocales order in main.dart.
Future<AppLocalizations> _loadLocalizations() {
  final deviceLocale = PlatformDispatcher.instance.locale;
  final resolved = deviceLocale.languageCode == 'en'
      ? const Locale('en')
      : const Locale('pt');
  return AppLocalizations.delegate.load(resolved);
}

class UkPoliceApi {
  /// =========================
  /// FETCH INCIDENTS FOR MAP
  /// =========================
  static void clearTrendCache() {
    _cachedTrend = null;
    _lastTrendFetch = null;
    _lastTrendArea = null;
  }

  static Future<List<MapIncident>> fetchForArea({
    required double lat,
    required double lng,
    required double radiusMeters,
  }) async {
    final List<MapIncident> allIncidents = [];
    final Set<String> seen = {};
    final distance = const Distance();
    final center = LatLng(lat, lng);
    final l10n = await _loadLocalizations();

    // Pega últimos 4 meses (já assumindo atraso de publicação)
    final monthsToFetch = _getLastMonths(count: 4, backMonths: 2);

    final client = http.Client();
    try {
      for (final month in monthsToFetch) {
        try {
          final url = Uri.parse(
            'https://data.police.uk/api/crimes-street/all-crime?lat=$lat&lng=$lng&date=$month',
          );

          final res = await client.get(url).timeout(const Duration(seconds: 4));
          if (res.statusCode != 200) {
            debugPrint(
                'ℹ️ BeeAware: Month $month not available (${res.statusCode}).');
            continue;
          }

          final decoded = jsonDecode(res.body);
          if (decoded is! List) continue;

          for (final row in decoded) {
            if (row is! Map) continue;

            final loc = row['location'];
            if (loc is! Map) continue;

            final latStr = loc['latitude']?.toString();
            final lngStr = loc['longitude']?.toString();
            if (latStr == null || lngStr == null) continue;

            final crimeLat = double.tryParse(latStr);
            final crimeLng = double.tryParse(lngStr);
            if (crimeLat == null || crimeLng == null) continue;

            final point = LatLng(crimeLat, crimeLng);
            final meters = distance.as(LengthUnit.Meter, center, point);
            if (meters > radiusMeters) continue;

            String streetName = l10n.locationNotSpecified;
            if (loc['street'] is Map) {
              final s = (loc['street']['name'] as String?)?.trim();
              if (s != null && s.isNotEmpty) streetName = s;
            }

            final category = (row['category'] as String?) ?? 'unknown';
            final outcome = row['outcome_status']?['category'];
            final categoryText = category.replaceAll('-', ' ');

            final description = outcome != null
                ? l10n.officialDescriptionWithOutcome(
                    categoryText, streetName, outcome as String, month)
                : l10n.officialDescriptionNoOutcome(
                    categoryText, streetName, month);

            final dedupeKey =
                '$crimeLat|$crimeLng|$category|$month|$streetName';
            if (seen.contains(dedupeKey)) continue;
            seen.add(dedupeKey);

            allIncidents.add(
              MapIncident(
                id: 'uk-${_generateFingerprint(
                  lat: crimeLat,
                  lng: crimeLng,
                  category: category,
                  month: month,
                  street: streetName,
                )}',
                location: point,
                severity: _mapSeverity(category),
                category: 'Police report',
                subcategory: category.replaceAll('-', ' '),
                description: description,
                dateTime: _parsePoliceMonth(month),
                isOfficial: true,
                source: 'UK Police',
              ),
            );
          }
        } catch (e) {
          debugPrint('⚠️ Police API error ($month): $e');
        }
      }
    } finally {
      client.close();
    }

    return allIncidents;
  }

  /// =========================
  /// TREND CACHE (FAST UX)
  /// =========================
  static String? _lastTrendArea;
  static List<MonthlyTrend>? _cachedTrend;
  static DateTime? _lastTrendFetch;

  static List<MonthlyTrend>? get cachedTrend => _cachedTrend;

  static Future<List<MonthlyTrend>> fetchTrend({
    required double lat,
    required double lng,
  }) async {
    final areaKey = '${lat.toStringAsFixed(1)}_${lng.toStringAsFixed(1)}';

    // se mudou a área, limpa cache e relógio
    if (_lastTrendArea != areaKey) {
      _cachedTrend = null;
      _lastTrendFetch = null;
      _lastTrendArea = areaKey;
    }

    // se já tem cache → devolve instant e atualiza em background
    if (_cachedTrend != null) {
      refreshTrendBackground(lat: lat, lng: lng);
      return _cachedTrend!;
    }

    final data = await _fetchTrendInternal(lat: lat, lng: lng);
    _cachedTrend = data;
    return data;
  }

  static Future<void> refreshTrendBackground({
    required double lat,
    required double lng,
  }) async {
    try {
      final data = await _fetchTrendInternal(lat: lat, lng: lng);
      _cachedTrend = data;
      _lastTrendFetch = DateTime.now();
    } catch (_) {}
  }

  static Future<List<MonthlyTrend>> _fetchTrendInternal({
    required double lat,
    required double lng,
  }) async {
    final now = DateTime.now();

    // evita refetch frequente
    if (_cachedTrend != null &&
        _lastTrendFetch != null &&
        now.difference(_lastTrendFetch!) < const Duration(hours: 12)) {
      return _cachedTrend!;
    }

    // ✅ pega o último mês disponível oficial (sem depender de ter crimes)
    final months = await _getLastMonthsSmart(
      count: 12,
      lat: lat,
      lng: lng,
    );

    final Map<String, int> counts = {};
    final client = http.Client();

    try {
      // ⚡ paralelismo controlado (web-friendly) + timeout
      for (final m in months) {
        await Future.delayed(const Duration(milliseconds: 35));
        try {
          final url = Uri.parse(
            'https://data.police.uk/api/crimes-street/all-crime?lat=$lat&lng=$lng&date=$m',
          );

          final res = await client.get(url).timeout(const Duration(seconds: 4));
          if (res.statusCode != 200) continue;

          final decoded = jsonDecode(res.body);
          if (decoded is List) {
            for (final crime in decoded) {
              if (crime is! Map) continue;

              final crimeMonth = crime['month'];
              if (crimeMonth is! String) continue;

              counts[crimeMonth] = (counts[crimeMonth] ?? 0) + 1;
            }
          }
        } catch (_) {}
      }
    } finally {
      client.close();
    }

    final trend = months.map((m) {
      final realCount = counts[m] ?? 0;

      return MonthlyTrend(
        month: _parsePoliceMonth(m),
        count: realCount,
      );
    }).toList();

    _lastTrendFetch = now;
    return trend;
  }

  /// =========================
  /// SMART MONTHS (CORRETO)
  /// =========================
  static Future<List<String>> _getLastMonthsSmart({
    required int count,
    required double lat,
    required double lng,
  }) async {
    final latest = await _findLatestAvailableMonth();

    final parts = latest.split('-');
    final base = DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);

    // Queremos retornar em ORDEM CRONOLÓGICA: mais antigo -> mais recente
    final List<String> months = [];
    for (int i = count - 1; i >= 0; i--) {
      final date = DateTime(base.year, base.month - i, 1);
      final monthStr = date.month.toString().padLeft(2, '0');
      months.add('${date.year}-$monthStr');
    }
    return months;
  }

  /// ✅ endpoint oficial: lista de meses disponíveis
  static Future<String> _findLatestAvailableMonth() async {
    final url = Uri.parse('https://data.police.uk/api/crimes-street-dates');

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) throw Exception('status ${res.statusCode}');

      final decoded = jsonDecode(res.body);

      if (decoded is List && decoded.isNotEmpty) {
        String? maxYm;

        for (final item in decoded) {
          if (item is! Map) continue;
          final ym = item['date'] as String?;
          if (ym == null || !ym.contains('-')) continue;

          // YYYY-MM permite comparação lexicográfica segura
          if (maxYm == null || ym.compareTo(maxYm) > 0) {
            maxYm = ym;
          }
        }

        if (maxYm != null) return maxYm;
      }
    } catch (e) {
      debugPrint('⚠️ crimes-street-dates failed: $e');
    }

    // fallback seguro: 3 meses atrás
    final now = DateTime.now();
    final fallback = DateTime(now.year, now.month - 3, 1);
    return '${fallback.year}-${fallback.month.toString().padLeft(2, '0')}';
  }

  /// =========================
  /// HELPERS
  /// =========================
  static String _generateFingerprint({
    required double lat,
    required double lng,
    required String category,
    required String month,
    String? street,
  }) {
    final raw = '$lat|$lng|$category|$month|${street ?? ''}';
    return raw.hashCode.toString();
  }

  static List<String> _getLastMonths({
    required int count,
    int backMonths = 2,
  }) {
    final List<String> months = [];
    final now = DateTime.now();
    final base = DateTime(now.year, now.month - backMonths, 1);

    for (int i = 0; i < count; i++) {
      final date = DateTime(base.year, base.month - i, 1);
      final mm = date.month.toString().padLeft(2, '0');
      months.add('${date.year}-$mm');
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
      case 'theft-from-the-person':
      case 'criminal-damage-arson':
      case 'public-order':
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

/// =========================
/// TREND MODEL
/// =========================
class MonthlyTrend {
  final DateTime month;
  final int count;

  MonthlyTrend({
    required this.month,
    required this.count,
  });
}
