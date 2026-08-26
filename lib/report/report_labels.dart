import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

/// Maps the canonical English category/subcategory values stored in
/// [ReportDraft] and sent to the backend to a localized display label.
/// The stored value never changes — only what's shown on screen does —
/// so existing Supabase rows keep displaying correctly after this app
/// starts writing new reports in any language.
class ReportLabels {
  /// Display label for an official (government-source) event's coarse
  /// category — the security_event_category enum value (e.g. "PROPERTY"),
  /// resolved at render time so it always reflects whatever locale is
  /// active right now, unlike a label baked in once at fetch time (see
  /// MapIncident.officialEventCategory's own header for why that mattered
  /// — the earlier version silently kept showing the fetch-time language
  /// after a user switched languages, since nothing re-fetches on a
  /// locale change alone). Reuses the community-report category strings
  /// where the concept lines up (VIOLENCE/PROPERTY) rather than inventing
  /// a parallel set for the same real-world idea; PUBLIC_SAFETY falls
  /// back to the generic "Police report" bucket since none of the
  /// existing labels fit its mix (weapon/drugs/disturbance/fire/
  /// emergency) well enough to pick just one.
  static String officialCategory(BuildContext context, String? eventCategory) {
    final loc = AppLocalizations.of(context)!;
    switch (eventCategory) {
      case 'ROAD_SAFETY':
        return loc.roadAccidentCategory;
      case 'VIOLENCE':
        return loc.categoryViolence;
      case 'PROPERTY':
        return loc.categoryTheft;
      default:
        return loc.policeReportCategory;
    }
  }

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
