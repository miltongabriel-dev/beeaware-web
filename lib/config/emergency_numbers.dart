/// Números de emergência variam por país — mostrar "999" para alguém no
/// Brasil ou na Espanha (onde esse número não significa nada) é um bug de
/// segurança, não só um detalhe visual.
class EmergencyNumbers {
  final String primary;
  final String? secondary;

  const EmergencyNumbers({required this.primary, this.secondary});
}

const Map<String, EmergencyNumbers> _byCountry = {
  // Reino Unido: 999 emergência, 101 não-emergência (polícia).
  'gb': EmergencyNumbers(primary: '999', secondary: '101'),
  // Brasil: 190 Polícia Militar, 192 SAMU (urgência médica) como segunda
  // linha mais comum.
  'br': EmergencyNumbers(primary: '190', secondary: '192'),
  // Espanha (e resto da UE): 112 único, cobre polícia/bombeiros/ambulância
  // — não existe uma linha "não-emergência" equivalente à 101 britânica.
  'es': EmergencyNumbers(primary: '112'),
};

EmergencyNumbers emergencyNumbersFor(String countryCode) =>
    _byCountry[countryCode.toLowerCase()] ?? _byCountry['gb']!;
