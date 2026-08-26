import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../l10n/app_localizations.dart';
import '../theme/beeaware_theme.dart';

/// The "Alertas" tab. No notifications backend exists yet (no Supabase
/// table, no push wiring) — this is a placeholder until that's built as
/// its own project, not a stub for missing UI work.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: BeeAwareTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: BeeAwareTheme.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    PhosphorIconsRegular.bellRinging,
                    color: BeeAwareTheme.primary,
                    size: 32,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  loc.alertsComingSoonTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: BeeAwareTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  loc.alertsComingSoonBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: BeeAwareTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
