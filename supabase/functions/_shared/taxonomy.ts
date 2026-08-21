// BeeAware Brasil roadmap — universal taxonomy (section 6.1).
//
// Mirrors the `security_event_category` enum in
// supabase/migrations/20260821120000_security_intelligence_foundation.sql —
// keep the two in sync by hand; there's no codegen linking them.
//
// event_type/event_subtype are intentionally NOT enums here either (same
// reasoning as the DB migration): adapters map source-specific categories
// onto this list, and the list grows with every new state source.

export type EventCategory =
  | "VIOLENCE"
  | "PROPERTY"
  | "PUBLIC_SAFETY"
  | "ROAD_SAFETY"
  | "COMMUNITY";

export const EVENT_TAXONOMY: Record<EventCategory, string[]> = {
  VIOLENCE: [
    "homicide",
    "attempted_homicide",
    "assault",
    "sexual_violence",
    "domestic_violence",
    "police_intervention",
    "kidnapping",
  ],
  PROPERTY: [
    "robbery",
    "theft",
    "burglary",
    "phone_robbery",
    "phone_theft",
    "vehicle_robbery",
    "vehicle_theft",
    "cargo_robbery",
  ],
  PUBLIC_SAFETY: [
    "weapon",
    "drugs",
    "disturbance",
    "suspicious_activity",
    "fire",
    "emergency",
  ],
  ROAD_SAFETY: [
    "accident",
    "serious_accident",
    "fatal_accident",
    "road_hazard",
    "road_closure",
  ],
  COMMUNITY: [
    "suspicious_activity",
    "harassment",
    "disorder",
    "unsafe_environment",
    "other",
  ],
};

export type GeoPrecision =
  | "EXACT"
  | "STREET"
  | "NEIGHBORHOOD"
  | "DISTRICT"
  | "MUNICIPALITY"
  | "STATE";

export type GeoAreaType =
  | "COUNTRY"
  | "STATE"
  | "MUNICIPALITY"
  | "NEIGHBORHOOD"
  | "RISP"
  | "AISP"
  | "CISP"
  | "AIS"
  | "RA";

export type SourceType = "official" | "community" | "news";

// Starting reliability per signal type (section 7.3) — the confidence
// engine multiplies this by location_confidence, time_confidence and a
// corroboration_adjustment; it is not the final confidence_score on its
// own.
export const SOURCE_RELIABILITY_BASELINE: Record<string, number> = {
  official_confirmed_record: 1.0,
  official_emergency_call: 0.9,
  major_media_precise_location: 0.85,
  established_local_journalism: 0.75,
  multiple_independent_reports: 0.7,
  verified_community_member: 0.55,
  single_anonymous_report: 0.3,
  ai_inference_alone: 0.0, // must never be shown to users as an event on its own
};
