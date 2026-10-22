import 'dart:ui';

import 'package:aware/utils/preferred_country_code.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('a location decides the country', () {
    expect(preferredCountryCode(const LatLng(-23.56, -46.66),
        deviceLocale: const Locale('en', 'GB')), 'br');
  });

  test('without a location, the device region decides', () {
    expect(preferredCountryCode(null, deviceLocale: const Locale('pt', 'BR')),
        'br');
    expect(preferredCountryCode(null, deviceLocale: const Locale('pt', 'PT')),
        'pt');
  });

  test('unknown or missing regions fall back to the UK', () {
    expect(preferredCountryCode(null, deviceLocale: const Locale('en', 'US')),
        'gb');
    expect(preferredCountryCode(null, deviceLocale: const Locale('pt')), 'gb');
  });
}
