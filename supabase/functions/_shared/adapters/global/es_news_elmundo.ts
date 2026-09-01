// BeeAware Global blueprint — ElMundoAdapter, Spain's second News
// Intelligence source. es_news.ts (La Vanguardia) is the direct model
// for this file's shape.
//
// Investigated live (2026-09-01): tried a dedicated "sucesos" section
// for El Mundo/El País/El Español/eldiario.es first (the pattern that
// made La Vanguardia's own source so effective) — none exist at that
// URL shape (all 404). El Mundo's general "España" feed
// (elmundo.es/rss/espana.xml) is a real, working, if more modest,
// second source: a live pull of 53 items found 2 genuine classifiable
// incidents (sexual assault and a molotov-cocktail attack, both in
// Ceuta) — lower yield than La Vanguardia's dedicated section (as
// expected for a general national feed vs. one already curated to be
// about incidents), but real, different-outlet coverage worth adding
// for volume, same reasoning as Brazil stacking several modest
// national portals (CNN Brasil, Metrópoles, UOL...) alongside G1.
//
// Standard RFC822 pubDate and a real guid per item — no special date
// handling needed (unlike Notícias ao Minuto's non-standard PT format).
// Multiple <category> tags per item exist but are topic/person tags
// (e.g. "Vox", "Pedro Sánchez"), not places — same free-text
// municipio-matching approach as La Vanguardia's own title+description
// path, not the (unavailable here) category-based shortcut.

import { classifyEsNews } from "./es_news_classifier.ts";
import { parseFeedItems } from "../../rss.ts";
import { findAreaName, stripAccentsLower } from "./geo_text_match_generic.ts";
import { MUNICIPIO_NAME } from "./es_crime.ts";
import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const FEED_URL = "https://www.elmundo.es/rss/espana.xml";
const MUNICIPIO_NAMES = Object.values(MUNICIPIO_NAME);

export class ElMundoAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "ES",
      name: "El Mundo — España",
      organisation: "Unidad Editorial",
      sourceType: "news",
      sourceUrl: FEED_URL,
      adapterName: "ElMundoAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "every 4 hours",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(FEED_URL);
    if (!res.ok) {
      throw new Error(`El Mundo feed request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "elmundo-espana-feed",
        payload: await res.text(),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const xml = record.payload as string;
    const items = parseFeedItems(xml);
    const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");

    const events: SecurityEvent[] = [];
    for (const item of items) {
      const mapped = classifyEsNews(item.title, item.subtitle);
      if (!mapped) continue;
      const [eventCategory, eventType, severity] = mapped;

      const municipio = findAreaName(
        stripAccentsLower(`${item.title} ${item.subtitle}`),
        MUNICIPIO_NAMES,
      );
      if (!municipio) continue;

      const occurredAt = item.pubDate ? new Date(item.pubDate) : undefined;
      if (!occurredAt || Number.isNaN(occurredAt.getTime())) continue;

      events.push({
        countryCode: "ES",
        sourceRecordId: item.guid,
        sourceType: "news",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        occurredAt: occurredAt.toISOString(),
        publishedAt: occurredAt.toISOString(),
        geoPrecision: "MUNICIPALITY",
        locationConfidence: municipalityLocationConfidence,
        district: municipio,
        occurrenceCount: 1,
        severity,
        confidenceScore: computeConfidenceScore({
          reliabilityGrade: "established_local_journalism",
          locationConfidence: municipalityLocationConfidence,
        }),
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
