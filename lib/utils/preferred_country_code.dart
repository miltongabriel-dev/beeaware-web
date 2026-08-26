import 'package:latlong2/latlong.dart';

/// Coarse country guess from a coordinate, used to pick which emergency
/// numbers to show (see emergency_numbers.dart) and which geocoding
/// country bias to apply. Shared between the Início dashboard and the
/// Mapa screen — both need the same guess from whatever location each one
/// currently has, so this stays a pure function of a nullable point rather
/// than living on either screen's own state.
String preferredCountryCode(LatLng? location) {
  if (location == null) return 'gb';

  final lat = location.latitude;
  final lng = location.longitude;

  // 🇬🇧 UK approx
  if (lat > 49 && lat < 61) return 'gb';

  // 🇧🇷 Brazil approx
  if (lat < 5 && lat > -35) return 'br';

  // 🇪🇸 Spain approx (mainland + Balearic Islands). A faixa de latitude
  // sozinha também cobriria Itália/Grécia/Turquia, então a longitude
  // entra aqui para não confundir o número de emergência do usuário.
  if (lat > 36 && lat < 44 && lng > -9.5 && lng < 3.5) return 'es';

  return 'gb';
}
