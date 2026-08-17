import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

/// Formats how long ago [date] was, localized. Shared by every place in the
/// app that shows "X minutes ago" style text, so the wording (and the
/// "just now" cutoff) is consistent everywhere.
String relativeTime(BuildContext context, DateTime date) {
  final loc = AppLocalizations.of(context)!;
  final diff = DateTime.now().difference(date);

  if (diff.inMinutes < 1) return loc.relativeTimeJustNow;
  if (diff.inMinutes < 60) return loc.relativeTimeMinutes(diff.inMinutes);
  if (diff.inHours < 24) return loc.relativeTimeHours(diff.inHours);
  return loc.relativeTimeDays(diff.inDays);
}
