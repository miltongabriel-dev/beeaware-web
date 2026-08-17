import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

/// Maps the canonical English category/subcategory values stored in
/// [ReportDraft] and sent to the backend to a localized display label.
/// The stored value never changes — only what's shown on screen does —
/// so existing Supabase rows keep displaying correctly after this app
/// starts writing new reports in any language.
class ReportLabels {
  static String category(BuildContext context, String value) {
    final loc = AppLocalizations.of(context)!;
    switch (value) {
      case 'Harassment':
        return loc.categoryHarassment;
      case 'Suspicious activity':
        return loc.categorySuspiciousActivity;
      case 'Theft':
        return loc.categoryTheft;
      case 'Violence':
        return loc.categoryViolence;
      case 'Drugs':
        return loc.categoryDrugs;
      default:
        return loc.other;
    }
  }

  static String subcategory(BuildContext context, String value) {
    final loc = AppLocalizations.of(context)!;
    switch (value) {
      case 'Verbal':
        return loc.subHarassmentVerbal;
      case 'Physical':
        return loc.subHarassmentPhysical;
      case 'Online':
        return loc.subHarassmentOnline;
      case 'Stalking':
        return loc.subHarassmentStalking;
      case 'Sexual':
        return loc.subHarassmentSexual;
      case 'Loitering':
        return loc.subSuspiciousLoitering;
      case 'Following someone':
        return loc.subSuspiciousFollowing;
      case 'Looking into cars':
        return loc.subSuspiciousCars;
      case 'Checking doors':
        return loc.subSuspiciousDoors;
      case 'Pickpocketing':
        return loc.subTheftPickpocketing;
      case 'Bike theft':
        return loc.subTheftBike;
      case 'Car break-in':
        return loc.subTheftCarBreakIn;
      case 'Shoplifting':
        return loc.subTheftShoplifting;
      case 'Fight':
        return loc.subViolenceFight;
      case 'Domestic':
        return loc.subViolenceDomestic;
      case 'Weapon involved':
        return loc.subViolenceWeapon;
      case 'Threats':
        return loc.subViolenceThreats;
      case 'Use':
        return loc.subDrugsUse;
      case 'Dealing':
        return loc.subDrugsDealing;
      case 'Suspicious exchange':
        return loc.subDrugsExchange;
      case 'Needles found':
        return loc.subDrugsNeedles;
      default:
        return loc.other;
    }
  }
}
