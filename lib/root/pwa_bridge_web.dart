import 'dart:js' as js;

/// Real web implementation — the `isPwaInstallable`/`triggerPwaInstall` JS
/// functions are defined in web/index.html's own install-prompt handling.
bool isPwaInstallable() {
  try {
    return js.context.hasProperty('isPwaInstallable') &&
        js.context.callMethod('isPwaInstallable') == true;
  } catch (_) {
    return false;
  }
}

void triggerPwaInstall() {
  js.context.callMethod('triggerPwaInstall');
}

/// True once the page is already running as an installed app — added to
/// the iOS home screen (`navigator.standalone`), or installed via
/// Chrome's own Android/desktop install prompt (`display-mode:
/// standalone`). The install banner (install_app_banner.dart) has
/// nothing useful to offer at that point, so it hides entirely instead
/// of pointing an already-installed visitor back at the App Store or a
/// second install prompt.
bool isRunningStandalone() {
  try {
    final mql =
        js.context.callMethod('matchMedia', ['(display-mode: standalone)']);
    final displayModeStandalone = mql != null && mql['matches'] == true;
    final iosStandalone = js.context['navigator']['standalone'] == true;
    return displayModeStandalone || iosStandalone;
  } catch (_) {
    return false;
  }
}

const _installBannerDismissedKey = 'bw_install_banner_dismissed';

/// Whether the visitor already closed the install banner once — checked
/// via localStorage (not just in-memory state) so it stays dismissed
/// across visits instead of reappearing on every fresh page load.
bool isInstallBannerDismissed() {
  try {
    return js.context['localStorage']
            .callMethod('getItem', [_installBannerDismissedKey]) ==
        '1';
  } catch (_) {
    return false;
  }
}

void dismissInstallBanner() {
  try {
    js.context['localStorage']
        .callMethod('setItem', [_installBannerDismissedKey, '1']);
  } catch (_) {}
}
