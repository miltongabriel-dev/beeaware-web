import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// One live-suggestions result — display text plus its already-known
/// coordinate, so selecting a suggestion never needs a second geocoding
/// round-trip (unlike HomeScreen's own suggestion list, which re-runs
/// _geocodeAddress on tap; not changed here, out of scope).
class AddressSuggestion {
  final String primary;
  final String secondary;
  final LatLng point;

  AddressSuggestion({
    required this.primary,
    required this.secondary,
    required this.point,
  });
}

/// Same `geocode` Edge Function HomeScreen's own search box already uses
/// for its live-as-you-type dropdown (see _fetchSuggestions there) —
/// reused here rather than re-implemented, and already unrestricted by
/// country (unlike geocodeAddress above), so it works for Brazil out of
/// the box.
Future<List<AddressSuggestion>> fetchAddressSuggestions(String query) async {
  if (query.trim().length < 3) return [];

  try {
    final url = Uri.parse(
      'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/geocode'
      '?q=${Uri.encodeComponent(query)}&limit=5',
    );

    final response = await http.get(url);
    if (response.statusCode != 200) return [];

    final decoded = json.decode(response.body);
    if (decoded is! List) return [];

    return decoded.whereType<Map<String, dynamic>>().map((item) {
      final display = (item['display_name'] as String? ?? '');
      final parts = display.split(',');
      final primary = parts.first.trim();
      final secondary =
          parts.length > 1 ? parts.sublist(1).join(',').trim() : '';
      final lat = double.tryParse('${item['lat']}');
      final lon = double.tryParse('${item['lon']}');
      return (lat != null && lon != null)
          ? AddressSuggestion(
              primary: primary.isEmpty ? display : primary,
              secondary: secondary,
              point: LatLng(lat, lon),
            )
          : null;
    }).whereType<AddressSuggestion>().toList();
  } catch (_) {
    return [];
  }
}

/// Nominatim address search, scoped to BeeAware's two current markets
/// (UK, Brazil) rather than unrestricted — an unrestricted query can
/// return an ambiguous top match from anywhere in the world for a common
/// place name. HomeScreen has its own separate, UK-only _geocodeAddress
/// for the main search box (unchanged, out of scope here) — this is a
/// second, Brazil-aware geocoder for Route Awareness, not a replacement
/// for it.
Future<LatLng?> geocodeAddress(String query) async {
  try {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeComponent(query)}&format=json&limit=1&countrycodes=gb,br',
    );

    final response = await http.get(url, headers: {
      'Accept': 'application/json',
    });

    if (response.statusCode != 200) return null;

    final decoded = json.decode(response.body);
    if (decoded is! List || decoded.isEmpty) return null;

    final lat = double.tryParse(decoded[0]['lat'] as String? ?? '');
    final lon = double.tryParse(decoded[0]['lon'] as String? ?? '');
    if (lat == null || lon == null) return null;

    return LatLng(lat, lon);
  } catch (_) {
    return null;
  }
}
