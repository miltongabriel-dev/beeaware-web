import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:pwa_install/pwa_install.dart' as pwa;
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../root/pwa_bridge_stub.dart'
    if (dart.library.js) '../../root/pwa_bridge_web.dart' as pwa_bridge;
import '../../theme/app_card.dart';
import '../../theme/beeaware_theme.dart';

/// Início-tab banner nudging mobile web visitors toward the real app:
/// an App Store link on iOS (there's no installable-PWA concept Apple
/// exposes the way Android's beforeinstallprompt does), the same
/// install-to-homescreen flow ProfileScreen's own button already
/// triggers on Android. Web-only, mobile-only (defaultTargetPlatform is
/// UA-sniffed by Flutter itself on web, so this doubles as the iOS-vs-
/// Android split too), and hidden once the visitor already runs the
/// installed app or has dismissed the banner — see pwa_bridge_web.dart
/// for how both are detected/persisted, since Flutter has no
/// first-class hook for either on its own.
class InstallAppBanner extends StatefulWidget {
  const InstallAppBanner({super.key});

  @override
  State<InstallAppBanner> createState() => _InstallAppBannerState();
}

class _InstallAppBannerState extends State<InstallAppBanner> {
  bool _dismissed = !kIsWeb || pwa_bridge.isInstallBannerDismissed();

  void _dismiss() {
    pwa_bridge.dismissInstallBanner();
    setState(() => _dismissed = true);
  }

  void _installAndroid() {
    if (pwa_bridge.isPwaInstallable()) {
      pwa_bridge.triggerPwaInstall();
    } else {
      pwa.PWAInstall().promptInstall_();
    }
  }

  void _openAppStore() {
    launchUrl(Uri.parse(AppConfig.appStoreUrl),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || _dismissed || pwa_bridge.isRunningStandalone()) {
      return const SizedBox.shrink();
    }

    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    if (!isIos && !isAndroid) return const SizedBox.shrink();

    final loc = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        border: Border.all(color: Colors.transparent),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: BeeAwareTheme.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                PhosphorIconsRegular.deviceMobile,
                color: BeeAwareTheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isIos
                        ? loc.installBannerIosTitle
                        : loc.installBannerAndroidTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: BeeAwareTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isIos
                        ? loc.installBannerIosBody
                        : loc.installBannerAndroidBody,
                    style: const TextStyle(
                      fontSize: 12,
                      color: BeeAwareTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  GestureDetector(
                    onTap: isIos ? _openAppStore : _installAndroid,
                    child: Text(
                      isIos
                          ? loc.installBannerIosCta
                          : loc.installBannerAndroidCta,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: BeeAwareTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _dismiss,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(PhosphorIconsRegular.x,
                    size: 16, color: BeeAwareTheme.textAux),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
