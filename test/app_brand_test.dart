import 'package:aware/config/app_brand.dart';
import 'package:aware/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(bool, String)> _brandFor(WidgetTester tester, Locale locale) async {
  late bool isVeAi;
  late String title;
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('pt'), Locale('pt', 'BR'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(builder: (context) {
      isVeAi = AppBrand.isVeAi(context);
      title = AppLocalizations.of(context)!.appTitle;
      return const SizedBox();
    }),
  ));
  return (isVeAi, title);
}

void main() {
  testWidgets('Brazilian Portuguese is branded VêAí', (tester) async {
    expect(await _brandFor(tester, const Locale('pt', 'BR')), (true, 'VêAí'));
  });

  testWidgets('European Portuguese and English stay BeeAware', (tester) async {
    expect(await _brandFor(tester, const Locale('pt', 'PT')),
        (false, 'BeeAware'));
    expect(await _brandFor(tester, const Locale('en', 'BR')),
        (false, 'BeeAware'));
  });

  test('a pt override follows the device region', () {
    // The test binding's device locale is en_US, so plain pt is kept.
    expect(AppBrand.resolveOverride(const Locale('pt')), const Locale('pt'));
    expect(AppBrand.resolveOverride(const Locale('en')), const Locale('en'));
    expect(AppBrand.resolveOverride(null), isNull);
  });
}
