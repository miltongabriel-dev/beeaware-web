import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Icon per canonical category/subcategory value — same English keys used
/// by [ReportLabels], kept neutral (never a literal weapon/violence icon).
/// Phosphor "regular" weight — see the app's visual audit (redesign step 4):
/// the app had zero icon identity of its own beyond stock Material icons.
class ReportIcons {
  static IconData category(String value) {
    switch (value) {
      case 'Harassment':
        return PhosphorIconsRegular.warningCircle;
      case 'Suspicious activity':
        return PhosphorIconsRegular.eye;
      case 'Theft':
        return PhosphorIconsRegular.lock;
      case 'Violence':
        return PhosphorIconsRegular.warningOctagon;
      case 'Drugs':
        return PhosphorIconsRegular.firstAid;
      default:
        return PhosphorIconsRegular.dotsThree;
    }
  }

  static IconData subcategory(String value) {
    switch (value) {
      case 'Verbal':
        return PhosphorIconsRegular.microphone;
      case 'Physical':
        return PhosphorIconsRegular.handPointing;
      case 'Online':
        return PhosphorIconsRegular.deviceMobile;
      case 'Stalking':
        return PhosphorIconsRegular.eyeSlash;
      case 'Sexual':
        return PhosphorIconsRegular.warningDiamond;
      case 'Loitering':
        return PhosphorIconsRegular.mapPinArea;
      case 'Following someone':
        return PhosphorIconsRegular.personSimpleWalk;
      case 'Looking into cars':
        return PhosphorIconsRegular.car;
      case 'Checking doors':
        return PhosphorIconsRegular.door;
      case 'Pickpocketing':
        return PhosphorIconsRegular.hand;
      case 'Bike theft':
        return PhosphorIconsRegular.bicycle;
      case 'Car break-in':
        return PhosphorIconsRegular.carSimple;
      case 'Shoplifting':
        return PhosphorIconsRegular.storefront;
      case 'Fight':
        return PhosphorIconsRegular.handFist;
      case 'Domestic':
        return PhosphorIconsRegular.house;
      case 'Weapon involved':
        return PhosphorIconsRegular.shieldWarning;
      case 'Threats':
        return PhosphorIconsRegular.megaphone;
      case 'Use':
        return PhosphorIconsRegular.pill;
      case 'Dealing':
        return PhosphorIconsRegular.arrowsLeftRight;
      case 'Suspicious exchange':
        return PhosphorIconsRegular.handshake;
      case 'Needles found':
        return PhosphorIconsRegular.syringe;
      default:
        return PhosphorIconsRegular.dotsThree;
    }
  }
}
