// BeeAware Brasil roadmap — shared normalize() body for Portuguese-
// language NATIONAL news portals with no structural per-article
// location signal (CNN Brasil, Metrópoles, UOL, Agência Brasil, Folha —
// unlike G1, whose article URL always embeds a real UF, or Diário
// Online, whose own regional focus lets Pará be tried first before this
// generic path). Every one of these determines location the same way:
// classify the text, try to name a state directly (geo_text_match.ts's
// findState), then a municipality within that state — skip entirely
// when no state can be named. An unlocalizable item from a national
// portal has nothing useful to add over one that's provably somewhere
// in Brazil but nowhere specific (this project doesn't have a BR-wide
// COUNTRY-level display path the way it does for BBC/GB — see
// nearby_news's own SQL — so a state-less BR row would just be
// invisible in the feed, not a softer fallback; skipping is honest
// about that rather than writing a row nothing will ever show).
//
// pubDate is parsed with parsePossiblyPtBrDate (rss.ts) rather than a
// bare `new Date()` for all five, not just UOL (the one verified to
// need it) — it already tries plain Date parsing first and only
// applies the Portuguese-locale rewrite as a fallback, so it's a safe
// superset for portals that don't need the rewrite.

import { classifyPtBrNews, stripAccentsLower } from "./pt_news_classifier.ts";
import { parsePossiblyPtBrDate, stripHtmlTags, type RssFeedItem } from "../../rss.ts";
import { findCity, findState, getMunicipiosForUf, prefetchMunicipios } from "./geo_text_match.ts";
import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type { SecurityEvent } from "../types.ts";

interface Candidate {
  item: RssFeedItem;
  subtitle: string;
  eventCategory: string;
  eventType: string;
  severity: string;
  occurredAt: Date;
  normalizedText: string;
  uf: string;
}

export async function eventsFromNationalPtBrItems(items: RssFeedItem[]): Promise<SecurityEvent[]> {
  const stateLocationConfidence = defaultLocationConfidence("STATE");
  const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");

  // First pass: classify and name each item's state via findState()
  // (pure regex, no IBGE call) before fetching anything, so every
  // distinct state this pull needs can be prefetched CONCURRENTLY
  // below instead of one state at a time as items are visited in feed
  // order — a feed naming several different states (CNN Brasil,
  // Metrópoles, UOL, Agência Brasil, Folha all share this function)
  // otherwise means that many sequential, uncached-across-runs real
  // IBGE round trips. Confirmed live 2026-11-02: Folha and ES-news
  // (also routed through here) were already landing within ~15s of
  // the Edge Function's ~150s hard limit, the same root cause that
  // pushed G1NewsAdapter and DiarioOnlineAdapter past it outright.
  const candidates: Candidate[] = [];
  const neededUfs = new Set<string>();
  for (const item of items) {
    const subtitle = stripHtmlTags(item.subtitle);
    const mapped = classifyPtBrNews(item.title, subtitle);
    if (!mapped) continue;
    const [eventCategory, eventType, severity] = mapped;

    const occurredAt = item.pubDate ? parsePossiblyPtBrDate(item.pubDate) : undefined;
    if (!occurredAt) continue;

    const normalizedText = stripAccentsLower(`${item.title} ${subtitle}`);
    const uf = findState(normalizedText);
    if (!uf) continue;
    neededUfs.add(uf);
    candidates.push({ item, subtitle, eventCategory, eventType, severity, occurredAt, normalizedText, uf });
  }

  await prefetchMunicipios([...neededUfs]);

  const events: SecurityEvent[] = [];
  for (const c of candidates) {
    const city = findCity(c.normalizedText, await getMunicipiosForUf(c.uf));
    const geoPrecision = city ? "MUNICIPALITY" : "STATE";
    const locationConfidence = city ? municipalityLocationConfidence : stateLocationConfidence;

    events.push({
      countryCode: "BR",
      stateCode: c.uf,
      sourceRecordId: c.item.guid,
      sourceType: "news",
      eventCategory: c.eventCategory as SecurityEvent["eventCategory"],
      eventType: c.eventType,
      occurredAt: c.occurredAt.toISOString(),
      publishedAt: c.occurredAt.toISOString(),
      geoPrecision,
      locationConfidence,
      state: c.uf,
      city: city?.nome,
      cityIbgeCode: city ? String(city.id) : undefined,
      occurrenceCount: 1,
      severity: c.severity,
      confidenceScore: computeConfidenceScore({
        reliabilityGrade: "established_local_journalism",
        locationConfidence,
      }),
      rawPayload: { title: c.item.title, subtitle: c.subtitle, link: c.item.link },
    });
  }
  return events;
}
