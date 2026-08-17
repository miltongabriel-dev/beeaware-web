import 'package:flutter/material.dart';

/// Icon per canonical category/subcategory value — same English keys used
/// by [ReportLabels], kept neutral (never a literal weapon/violence icon).
class ReportIcons {
  static IconData category(String value) {
    switch (value) {
      case 'Harassment':
        return Icons.warning_amber_rounded;
      case 'Suspicious activity':
        return Icons.remove_red_eye_outlined;
      case 'Theft':
        return Icons.lock_outline;
      case 'Violence':
        return Icons.report_gmailerrorred;
      case 'Drugs':
        return Icons.medical_services_outlined;
      default:
        return Icons.more_horiz;
    }
  }

  static IconData subcategory(String value) {
    switch (value) {
      case 'Verbal':
        return Icons.record_voice_over_outlined;
      case 'Physical':
        return Icons.front_hand_outlined;
      case 'Online':
        return Icons.smartphone_outlined;
      case 'Stalking':
        return Icons.visibility_outlined;
      case 'Sexual':
        return Icons.report_outlined;
      case 'Loitering':
        return Icons.person_pin_circle_outlined;
      case 'Following someone':
        return Icons.directions_walk_outlined;
      case 'Looking into cars':
        return Icons.directions_car_outlined;
      case 'Checking doors':
        return Icons.sensor_door_outlined;
      case 'Pickpocketing':
        return Icons.pan_tool_outlined;
      case 'Bike theft':
        return Icons.pedal_bike_outlined;
      case 'Car break-in':
        return Icons.no_crash_outlined;
      case 'Shoplifting':
        return Icons.storefront_outlined;
      case 'Fight':
        return Icons.personal_injury_outlined;
      case 'Domestic':
        return Icons.home_outlined;
      case 'Weapon involved':
        return Icons.gpp_bad_outlined;
      case 'Threats':
        return Icons.campaign_outlined;
      case 'Use':
        return Icons.medication_outlined;
      case 'Dealing':
        return Icons.swap_horiz_outlined;
      case 'Suspicious exchange':
        return Icons.compare_arrows_outlined;
      case 'Needles found':
        return Icons.vaccines_outlined;
      default:
        return Icons.more_horiz;
    }
  }
}
