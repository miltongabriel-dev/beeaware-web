/// No-op implementation used on Android/iOS/desktop — PWA installability
/// is a web-only concept, and `dart:js` (needed for the real
/// implementation in pwa_bridge_web.dart) can't even be imported on these
/// platforms, so this file exists purely to satisfy the conditional
/// import in profile_screen.dart.
bool isPwaInstallable() => false;

void triggerPwaInstall() {}
