import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Nominatim's usage policy requires a User-Agent identifying the app —
/// requests without one are blocked/rate-limited, which is exactly why
/// reverseGeocode() and geocodeAddress() below were silently returning
/// null (the location pill showing "Location Unavailable" even with a
/// perfectly good GPS fix). Same fix as the map preview card's tile
/// requests, same identifier.
const Map<String, String> _nominatimHeaders = {
  'Accept': 'application/json',
  'User-Agent': 'io.beeaware.app (BeeAware iOS/Android app)',
};

/// URL for the `geocode` Edge Function (supabase/functions/geocode) —
/// shared by fetchAddressSuggestions below and HomeScreen's own
/// _fetchSuggestions, so both send the same location bias.
Uri geocodeSuggestionsUri(String query, {LatLng? near, int limit = 5}) {
  return Uri.https(
    'brjzkdtkmewbodpqjhkj.supabase.co',
    '/functions/v1/geocode',
    {
      'q': query,
      'limit': '$limit',
      if (near != null) 'lat': '${near.latitude}',
      if (near != null) 'lon': '${near.longitude}',
    },
  );
}

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

  /// What a field should actually be filled with on selection — `primary`
  /// alone is only the text before the first comma (e.g. a bare house
  /// number like "96"), which reads as a broken/incomplete address once
  /// it's the only thing left in the field.
  String get full => secondary.isEmpty ? primary : '$primary, $secondary';
}

/// Same `geocode` Edge Function HomeScreen's own search box already uses
/// for its live-as-you-type dropdown (see _fetchSuggestions there) —
/// reused here rather than re-implemented, and already unrestricted by
/// country (unlike geocodeAddress above), so it works for Brazil out of
/// the box.
///
/// [near] biases results toward that point (the function forwards it to
/// Photon) — without it a short query like "Copacaba" also returns
/// Colombian and Bolivian places ahead of the one in Rio.
Future<List<AddressSuggestion>> fetchAddressSuggestions(
  String query, {
  LatLng? near,
}) async {
  if (query.trim().length < 3) return [];

  try {
    final url = geocodeSuggestionsUri(query, near: near);

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
/// Reverse geocode a point into a short "City, State" label — used by the
/// Início dashboard's location card. Same Nominatim host and
/// UK/Brazil-only scoping as [geocodeAddress] above; falls back through
/// city/town/village since Nominatim doesn't always populate `city`.
Future<String?> reverseGeocode(LatLng point) async {
  try {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse'
      '?lat=${point.latitude}&lon=${point.longitude}&format=json&countrycodes=gb,br',
    );

    final response = await http.get(url, headers: _nominatimHeaders);

    if (response.statusCode != 200) return null;

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) return null;

    final address = decoded['address'];
    if (address is! Map<String, dynamic>) return null;

    final city = address['city'] ?? address['town'] ?? address['village'];
    final state = address['state'];

    if (city == null && state == null) return null;
    if (city != null && state != null) return '$city, $state';
    return (city ?? state) as String;
  } catch (_) {
    return null;
  }
}

Future<LatLng?> geocodeAddress(String query) async {
  try {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeComponent(query)}&format=json&limit=1&countrycodes=gb,br',
    );

    final response = await http.get(url, headers: _nominatimHeaders);

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
