// BeeAware Global blueprint — BbcNewsAdapter, the first UK News
// Intelligence source. G1NewsAdapter (adapters/br/g1_news.ts) is the
// direct model for this file's shape and its whole "known, accepted
// failure modes" approach — see that file's header for the fuller
// rationale; this one only documents what's genuinely different for a UK
// source.
//
// Feed: https://feeds.bbci.co.uk/news/england/rss.xml (verified live
// 2026-08-27, no auth, follows an http->https redirect cleanly). Unlike
// G1's per-article URL (which embeds a real Brazilian state code —
// g1.globo.com/{uf}/...), a BBC article URL carries no location at all
// (https://www.bbc.co.uk/news/articles/{id}) — there is no free,
// structural location signal to key off here. Rather than guess a
// county/city from free text (a real project, not attempted in this
// pass — no UK equivalent of IBGE's municipality list or MG/BA's IBGE-
// code join exists in this codebase), every event from this adapter is
// tagged geoPrecision COUNTRY, countryCode "GB", no stateCode/city at
// all — same shape as UnodcAdapter's own country-level rows (its own
// COUNTRY precedent in this project, unodc.ts). This is deliberately
// coarser than G1's per-state tagging; nearby_news's own SQL (see
// 20260828100000_nearby_news_country_fallback.sql) only reaches this
// source at all once a point resolves to nowhere in Brazil, and labels
// it "whole of the UK", never a county/city, matching what's actually
// known.
//
// Classifier: same keyword-allowlist approach as G1, in English. Verified
// against a real live pull of 22 items, 2026-08-27 — 7 correctly
// classified, 2 correctly excluded (a data-breach story that would
// otherwise have matched "steal", a disease-outbreak story that matched
// "on par with"), 1 false positive found and fixed: "gatecrashes" (a
// party-crashing pun, nothing to do with a road accident) contains
// "crash" as a substring — added to EXCLUSION_KEYWORDS rather than
// trying to make "crash" itself stricter, since every other real
// "crash" hit in the sample (two separate genuine fatal collisions) was
// a plain, correct match. Bare "died"/"dead"/"killed" are deliberately
// NOT classifier triggers on their own — same reasoning as G1 dropping
// "encontrado morto": a workplace death (a father and son falling into a
// silage tank) and a natural-disaster death toll (Nepal flooding) both
// appeared in the same real pull and share no real distinguishing
// keyword from an actual homicide. They're only used here to upgrade an
// already-matched ROAD_SAFETY "accident" to "fatal_accident" — a strictly
// narrower use than a standalone trigger.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import { parseFeedItems } from "../../rss.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const FEED_URL = "https://feeds.bbci.co.uk/news/england/rss.xml";

function stripLower(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

// Order matters: classify() returns the FIRST match, so a more specific
// phrase (e.g. "fatally stabbed") must be listed before the broader word
// it contains ("stabbed") or it would never be reached.
const KEYWORD_MAP: [string, string, string, string][] = [
  ["fatally stabbed", "VIOLENCE", "homicide", "high"],
  ["stabbed to death", "VIOLENCE", "homicide", "high"],
  ["shot dead", "VIOLENCE", "homicide", "high"],
  ["murder", "VIOLENCE", "homicide", "high"],
  ["manslaughter", "VIOLENCE", "homicide", "high"],
  ["sexual assault", "VIOLENCE", "sexual_violence", "high"],
  ["indecent assault", "VIOLENCE", "sexual_violence", "high"],
  ["rape", "VIOLENCE", "sexual_violence", "high"],
  ["kidnap", "VIOLENCE", "kidnapping", "high"],
  ["abducted", "VIOLENCE", "kidnapping", "high"],
  ["knife attack", "PUBLIC_SAFETY", "weapon", "high"],
  ["stabbing", "PUBLIC_SAFETY", "weapon", "high"],
  ["stabbed", "VIOLENCE", "assault", "high"],
  ["shooting", "PUBLIC_SAFETY", "weapon", "high"],
  ["shot", "PUBLIC_SAFETY", "weapon", "medium"],
  ["brawl", "VIOLENCE", "assault", "medium"],
  ["assault", "VIOLENCE", "assault", "medium"],
  ["mugging", "PROPERTY", "robbery", "medium"],
  ["mugged", "PROPERTY", "robbery", "medium"],
  ["robbery", "PROPERTY", "robbery", "medium"],
  ["robbed", "PROPERTY", "robbery", "medium"],
  ["burglary", "PROPERTY", "burglary", "medium"],
  ["burgled", "PROPERTY", "burglary", "medium"],
  ["arson", "PUBLIC_SAFETY", "fire", "medium"],
  ["house fire", "PUBLIC_SAFETY", "fire", "medium"],
  ["wildfire", "PUBLIC_SAFETY", "fire", "medium"],
  ["blaze", "PUBLIC_SAFETY", "fire", "medium"],
  ["drug dealing", "PUBLIC_SAFETY", "drugs", "medium"],
  ["drug bust", "PUBLIC_SAFETY", "drugs", "medium"],
  ["drugs", "PUBLIC_SAFETY", "drugs", "low"],
  ["pile-up", "ROAD_SAFETY", "accident", "medium"],
  ["crash", "ROAD_SAFETY", "accident", "low"],
  ["collision", "ROAD_SAFETY", "accident", "low"],
];

// See header comment for the real cases each of these was added for.
const EXCLUSION_KEYWORDS = [
  "hacker", "data breach", "cyber attack", "ransomware", "figures show",
  "study finds", "statistics", "compared to last year", "on par with",
  "gatecrash",
];

// Only used to upgrade an already-matched ROAD_SAFETY "accident" to
// fatal_accident — never a standalone trigger. See header comment.
const DEATH_WORDS = ["died", "dead", "killed", "fatal", "death"];

function classify(title: string, description: string): [string, string, string] | undefined {
  const normalized = stripLower(`${title} ${description}`);
  if (EXCLUSION_KEYWORDS.some((kw) => normalized.includes(kw))) return undefined;

  for (const [keyword, eventCategory, eventType, severity] of KEYWORD_MAP) {
    if (!normalized.includes(keyword)) continue;
    if (eventType === "accident" && DEATH_WORDS.some((w) => normalized.includes(w))) {
      return [eventCategory, "fatal_accident", "high"];
    }
    return [eventCategory, eventType, severity];
  }
  return undefined;
}

export class BbcNewsAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "GB",
      name: "BBC News - England",
      organisation: "British Broadcasting Corporation",
      sourceType: "news",
      sourceUrl: FEED_URL,
      adapterName: "BbcNewsAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "every 4 hours",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(FEED_URL);
    if (!res.ok) {
      throw new Error(`BBC feed request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "bbc-england-feed",
        payload: await res.text(),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const xml = record.payload as string;
    const items = parseFeedItems(xml);
    const countryLocationConfidence = defaultLocationConfidence("COUNTRY");

    const events: SecurityEvent[] = [];
    for (const item of items) {
      const mapped = classify(item.title, item.subtitle);
      if (!mapped) continue;
      const [eventCategory, eventType, severity] = mapped;

      const occurredAt = item.pubDate ? new Date(item.pubDate) : undefined;
      if (!occurredAt || Number.isNaN(occurredAt.getTime())) continue;

      events.push({
        countryCode: "GB",
        sourceRecordId: item.guid,
        sourceType: "news",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        occurredAt: occurredAt.toISOString(),
        publishedAt: occurredAt.toISOString(),
        geoPrecision: "COUNTRY",
        locationConfidence: countryLocationConfidence,
        occurrenceCount: 1,
        severity,
        confidenceScore: computeConfidenceScore({
          reliabilityGrade: "established_local_journalism",
          locationConfidence: countryLocationConfidence,
        }),
        // See g1_news.ts's own header for why this lives in rawPayload
        // rather than original_category.
        rawPayload: { title: item.title, subtitle: item.subtitle, link: item.link },
      });
    }
    return events;
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(FEED_URL);
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on feed` };
      }
      const xml = await res.text();
      const items = parseFeedItems(xml);
      if (items.length === 0) {
        return { status: "RED", message: "No <item> entries found — feed markup may have changed" };
      }
      return { status: "GREEN", lastDataDate: new Date().toISOString().slice(0, 10) };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
