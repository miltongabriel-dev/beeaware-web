class AppConfig {
  /// Delay before a submitted incident becomes visible on the map.
  /// Read this everywhere the delay is shown or applied — never hardcode it.
  static const Duration incidentVisibilityDelay = Duration(minutes: 1);

  /// Whether the token/search-credit system (gating, badge, "buy more"
  /// prompts) is active. Off because there's no real payment behind it yet
  /// — searches are unlimited while this is false. Flip back on once
  /// purchases actually charge something.
  static const bool tokensEnabled = false;

  /// Public App Store listing — the iOS variant of the Início install
  /// banner (lib/home/widgets/install_app_banner.dart) sends visitors
  /// here directly, since iOS has no installable-PWA prompt equivalent
  /// to Android's beforeinstallprompt.
  static const String appStoreUrl = 'https://apps.apple.com/app/id6809385683';
}
