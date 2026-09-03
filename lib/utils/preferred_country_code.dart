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

  // 🇵🇹 Portugal (continente) — checado antes da Espanha porque essa
  // faixa toda já cai dentro da caixa mais larga da Espanha logo abaixo.
  if (lat > 36.8 && lat < 42.3 && lng > -9.6 && lng < -6.1) return 'pt';

  // 🇪🇸 Spain approx (mainland + Balearic Islands). A faixa de latitude
  // sozinha também cobriria Itália/Grécia/Turquia, então a longitude
  // entra aqui para não confundir o número de emergência do usuário.
  if (lat > 36 && lat < 44 && lng > -9.5 && lng < 3.5) return 'es';

  // 🇫🇷 França (continente + Córsega) — checado antes do Reino Unido:
  // sem isso, o norte da França cai na faixa de latitude 49-61 do 'gb'
  // logo abaixo e ganha o 999 errado (encontrado ao investigar por que
  // o mapa de calor "sumia" na Alemanha/França — Berlim tinha o mesmo
  // problema, ver bloco 🇩🇪 abaixo).
  if (lat > 41.2 && lat < 51.2 && lng > -5.2 && lng < 9.6) return 'fr';

  // 🇩🇪 Alemanha — mesma razão do bloco da França: precisa vir antes do
  // 'gb' largo logo abaixo, senão praticamente toda a Alemanha (lat
  // 47-55) cai como Reino Unido.
  if (lat > 47.2 && lat < 55.2 && lng > 5.8 && lng < 15.1) return 'de';

  // 🇬🇧 UK approx — agora com longitude para não engolir Alemanha/França
  // (checadas acima) nem os países vizinhos que ficam na mesma faixa de
  // latitude.
  if (lat > 49 && lat < 61 && lng > -8.7 && lng < 2) return 'gb';

  // 🇧🇷 Brazil approx
  if (lat < 5 && lat > -35) return 'br';

  return 'gb';
}
