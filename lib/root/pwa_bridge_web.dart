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
