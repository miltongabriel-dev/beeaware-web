// BeeAware Global blueprint — confidence score (Phase 0).
//
// SOURCE_RELIABILITY_BASELINE (taxonomy.ts) was written months before
// this file, documented as "the confidence engine multiplies this by
// location_confidence, time_confidence and a corroboration_adjustment"
// — but nothing ever imported it. Every adapter (prf.ts, rj_isp.ts,
// pa_segup.ts) has hardcoded confidenceScore/locationConfidence to 1.0
// since it was written, which is a real, live inconsistency: an
// exact-coordinate PRF accident and a whole-municipality RJ-ISP monthly
// aggregate currently claim identical confidence, even though one is
// vastly more geographically precise than the other. This is the first
// real implementation of that formula.
//
// Deliberately narrower than the blueprint's own sketch ("source grade,
// geo precision, freshness, coverage, cross-source agreement"): no
// freshness-decay term. These are official historical crime-statistics
// records — a confirmed January homicide doesn't become less true in
// August. Staleness here is a property of the *source* (how current is
// our picture of an area), already tracked via security_sources.
// last_data_date and health status, not a reason to discount a
// specific past event's own confidence. Corroboration (cross-source
// agreement) also isn't implemented — there's no deduplication/
// cross-source-matching engine yet (blueprint Phase 6), so it's fixed
// at 1.0 (no adjustment) rather than a value this code can't actually
// compute.

import type { GeoPrecision } from "./taxonomy.ts";
import { SOURCE_RELIABILITY_BASELINE } from "./taxonomy.ts";

// How much a source's own precision claim is trusted, absent a more
// specific per-event value. An exact PRF/PA-SEGUP coordinate is a real
// GPS-adjacent point; an RJ-ISP monthly count only pins an event down to
// "somewhere in this municipality" — the further down this list, the
// more a displayed pin/score would overstate what's actually known.
const DEFAULT_LOCATION_CONFIDENCE: Record<GeoPrecision, number> = {
  EXACT: 1.0,
  STREET: 0.9,
  NEIGHBORHOOD: 0.75,
  DISTRICT: 0.6,
  MUNICIPALITY: 0.5,
  STATE: 0.3,
  // Added for UnodcAdapter (Phase 1) — a whole-country statistic is
  // genuinely the coarsest tier this schema has, so it gets the lowest
  // location_confidence, not a repeat of STATE's.
  COUNTRY: 0.2,
};

export function defaultLocationConfidence(geoPrecision: GeoPrecision): number {
  return DEFAULT_LOCATION_CONFIDENCE[geoPrecision];
}

export type ReliabilityGrade = keyof typeof SOURCE_RELIABILITY_BASELINE;

export interface ConfidenceInput {
  reliabilityGrade: ReliabilityGrade;
  locationConfidence: number;
}

// confidence_score = source_reliability_baseline × location_confidence.
// Kept as a named function (not inlined per adapter) so the one real
// formula this app has is defined exactly once — see the file header
// for why freshness/corroboration aren't factors here yet.
export function computeConfidenceScore({ reliabilityGrade, locationConfidence }: ConfidenceInput): number {
  const baseline = SOURCE_RELIABILITY_BASELINE[reliabilityGrade];
  const clampedLocation = Math.max(0, Math.min(1, locationConfidence));
  return Math.round(baseline * clampedLocation * 1000) / 1000; // matches confidence_score's numeric(4,3)
}
