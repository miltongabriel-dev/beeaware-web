import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// BeeAware is branded VêAí for Brazilian Portuguese (pt_BR) — same app,
/// same backend, a Portuguese name the Brazilian market relates to. The
/// store listings (App Store Connect / Play Console pt-BR localization),
/// the home-screen name (ios/Runner/pt-BR.lproj/InfoPlist.strings,
/// android/app/src/main/res/values-pt-rBR/strings.xml) and the in-app
/// brand all follow the same rule, so a user never sees VêAí on the
/// store and BeeAware inside the app. Text that names the brand lives in
/// lib/l10n/app_pt_BR.arb; this class covers the logos.
class AppBrand {
  static bool isVeAi(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return locale.languageCode == 'pt' && locale.countryCode == 'BR';
  }

  /// MaterialApp locale for a manual language override. The picker stores
  /// only a language code (LocaleState), so a Brazilian who picks
  /// "Português" would otherwise resolve to plain `pt` and lose the VêAí
  /// brand — the device's region decides which Portuguese they get.
  static Locale? resolveOverride(Locale? override) {
    if (override?.languageCode != 'pt') return override;
    return PlatformDispatcher.instance.locale.countryCode == 'BR'
        ? const Locale('pt', 'BR')
        : override;
  }

  /// Horizontal-ish logo for headers and hero areas. VêAí's logo is
  /// stacked (mascot above the name), so callers size it by height.
  static String wordmarkAsset(BuildContext context) {
    if (isVeAi(context)) return 'assets/logo/veai_logo.png';
    return Localizations.localeOf(context).languageCode == 'pt'
        ? 'assets/logo/beeaware_wordmark_pt.png'
        : 'assets/logo/beeaware_wordmark_en.png';
  }

  static Widget symbol(BuildContext context, {double? width, double? height}) {
    if (isVeAi(context)) {
      return Image.asset('assets/logo/veai_symbol.png',
          width: width, height: height);
    }
    return SvgPicture.asset('assets/logo/beeaware_symbol.svg',
        width: width, height: height);
  }
}
