import 'package:flutter/widgets.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'map_incident.dart';

/// Icon per official incident type, drawn inside BeeIncidentPin's badge so
/// the map says *what* happened, not just how severe it was (the plain
/// 10px severity dot it replaces was hard for users to read).
///
/// Same rule as ReportIcons: neutral glyphs only, never a literal weapon
/// or violence icon. Sexual and domestic violence reuse ReportIcons' own
/// glyphs so community reports and official data read the same way.
class IncidentIcons {
  /// Brazilian sources put the taxonomy event_type in `category`
  /// (e.g. "phone_robbery"); UK Police puts its category, dashes turned
  /// into spaces, in `subcategory` (e.g. "anti social behaviour") with
  /// `category` fixed to "Police report". Both are normalised to
  /// snake_case and looked up in one table.
  static IconData of(MapIncident incident) {
    return _byType[_normalise(incident.category)] ??
        _byType[_normalise(incident.subcategory)] ??
        _byEventCategory[incident.officialEventCategory] ??
        PhosphorIconsRegular.warningCircle;
  }

  static String _normalise(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');

  static final Map<String, IconData> _byType = {
    // Phone
    'phone_robbery': PhosphorIconsRegular.deviceMobile,
    'phone_theft': PhosphorIconsRegular.deviceMobile,
    // Vehicle
    'vehicle_robbery': PhosphorIconsRegular.car,
    'vehicle_theft': PhosphorIconsRegular.car,
    'cargo_robbery': PhosphorIconsRegular.car,
    'vehicle_crime': PhosphorIconsRegular.car,
    'bicycle_theft': PhosphorIconsRegular.bicycle,
    // Robbery / theft
    'robbery': PhosphorIconsRegular.handGrabbing,
    'theft_from_the_person': PhosphorIconsRegular.handGrabbing,
    'theft': PhosphorIconsRegular.handbag,
    'other_theft': PhosphorIconsRegular.handbag,
    'shoplifting': PhosphorIconsRegular.storefront,
    'burglary': PhosphorIconsRegular.door,
    // Violence
    'homicide': PhosphorIconsRegular.warningOctagon,
    'attempted_homicide': PhosphorIconsRegular.warningOctagon,
    'assault': PhosphorIconsRegular.warningOctagon,
    'kidnapping': PhosphorIconsRegular.warningOctagon,
    'police_intervention': PhosphorIconsRegular.warningOctagon,
    'violent_crime': PhosphorIconsRegular.warningOctagon,
    'sexual_violence': PhosphorIconsRegular.warningDiamond,
    'sexual_offences': PhosphorIconsRegular.warningDiamond,
    'domestic_violence': PhosphorIconsRegular.house,
    // Public safety
    'weapon': PhosphorIconsRegular.shieldWarning,
    'possession_of_weapons': PhosphorIconsRegular.shieldWarning,
    'drugs': PhosphorIconsRegular.pill,
    'disturbance': PhosphorIconsRegular.megaphone,
    'anti_social_behaviour': PhosphorIconsRegular.megaphone,
    'public_order': PhosphorIconsRegular.megaphone,
    'suspicious_activity': PhosphorIconsRegular.eye,
    'fire': PhosphorIconsRegular.flame,
    'criminal_damage_arson': PhosphorIconsRegular.flame,
    'emergency': PhosphorIconsRegular.siren,
    // Road safety
    'accident': PhosphorIconsRegular.trafficSign,
    'serious_accident': PhosphorIconsRegular.trafficSign,
    'fatal_accident': PhosphorIconsRegular.trafficSign,
    'road_hazard': PhosphorIconsRegular.trafficCone,
    'road_closure': PhosphorIconsRegular.trafficCone,
  };

  /// Fallback when the fine-grained type is unknown or missing — the
  /// security_event_category enum (supabase/functions/_shared/taxonomy.ts).
  static const Map<String, IconData> _byEventCategory = {
    'VIOLENCE': PhosphorIconsRegular.warningOctagon,
    'PROPERTY': PhosphorIconsRegular.handbag,
    'PUBLIC_SAFETY': PhosphorIconsRegular.shieldWarning,
    'ROAD_SAFETY': PhosphorIconsRegular.trafficSign,
  };
}
