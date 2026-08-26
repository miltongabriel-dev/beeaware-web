import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/emergency_numbers.dart';
import '../l10n/app_localizations.dart';
import 'beeaware_theme.dart';

/// The red "SOS {number}" pill — shared by the Início dashboard and the
/// Mapa screen (previously a private widget on the map screen only, now
/// shown on both so the emergency shortcut is reachable from the very
/// first screen the app opens to, not only after switching tabs).
class SosButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const SosButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SeverityColors.high,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(PhosphorIconsRegular.siren,
                  size: 16, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bottom sheet SosButton opens — call emergency / non-emergency
/// numbers for whatever country the current location resolves to. Same
/// content on both screens, just extracted so it isn't duplicated.
void showEmergencySheet(BuildContext context, String countryCode) {
  final numbers = emergencyNumbersFor(countryCode);
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (sheetContext) {
      final loc = AppLocalizations.of(sheetContext)!;
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              loc.emergencyServices,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(PhosphorIconsRegular.siren),
              label: Text(loc.callEmergencyNumber(numbers.primary)),
              style: ElevatedButton.styleFrom(
                backgroundColor: SeverityColors.high,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final uri = Uri.parse('tel:${numbers.primary}');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
            if (numbers.secondary != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(PhosphorIconsRegular.phone),
                label: Text(loc.callNonEmergencyNumber(numbers.secondary!)),
                onPressed: () async {
                  final uri = Uri.parse('tel:${numbers.secondary}');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
              ),
            ],
            const SizedBox(height: 12),
            Text(
              loc.emergencyDisclaimer,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: BeeAwareTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    },
  );
}
