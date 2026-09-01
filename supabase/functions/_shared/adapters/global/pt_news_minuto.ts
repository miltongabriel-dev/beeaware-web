// BeeAware Global blueprint — NoticiasAoMinutoAdapter, Portugal's second
// News Intelligence source. pt_news.ts (RTP) is the direct model for
// this file's shape; the only real difference is the feed itself.
//
// Investigated live (2026-09-01): RTP's own "País" feed only holds 50
// items and yielded 3 classifiable incidents in a real pull — genuinely
// sparse, since only 6 PT events total made it into security_events
// after the first real run. Looked for a denser Portuguese source with
// the same "national incidents" focus Brazil's multiple news portals
// already give it: noticiasaominuto.com/rss/pais (found via its own
// landing page's advertised feed list at /rss) is a much better fit —
// 490 items in one pull, 139 of them (28%) genuinely classifiable
// incidents with real concelho names already in the title (Ansião,
// Albufeira, Évora, Fátima, Sacavém, Foz Côa...). Same "reuse Brazil's
// own classifier" reasoning as pt_news.ts: classifyPtBrNews's vocabulary
// is standard Portuguese, nothing Brazilian-slang-specific in it.
//
// pubDate here is "YYYY-MM-DD HH:MM:SS" (e.g. "2026-09-01 15:55:12"),
// not RFC822 — confirmed live that plain `new Date()` (V8/Deno) parses
// this correctly as-is, so no custom date parser is needed the way
// rss.ts's parsePossiblyPtBrDate exists for UOL's non-English weekday/
// month names.

import { classifyPtBrNews } from "../br/pt_news_classifier.ts";
import { parseFeedItems } from "../../rss.ts";
import { findAreaName, stripAccentsLower } from "./geo_text_match_generic.ts";
import { CONCELHO_NAME } from "./pt_crime.ts";
import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const FEED_URL = "https://www.noticiasaominuto.com/rss/pais";
const CONCELHO_NAMES = Object.values(CONCELHO_NAME);

export class NoticiasAoMinutoAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "PT",
      name: "Notícias ao Minuto — País",
      organisation: "Notícias ao Minuto",
      sourceType: "news",
      sourceUrl: FEED_URL,
      adapterName: "NoticiasAoMinutoAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "every 4 hours",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(FEED_URL);
    if (!res.ok) {
      throw new Error(`Notícias ao Minuto feed request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "noticiasaominuto-pais-feed",
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
      const mapped = classifyPtBrNews(item.title, item.subtitle);
      if (!mapped) continue;
      const [eventCategory, eventType, severity] = mapped;

      const concelho = findAreaName(
        stripAccentsLower(`${item.title} ${item.subtitle}`),
        CONCELHO_NAMES,
      );
      if (!concelho) continue;

      const occurredAt = item.pubDate ? new Date(item.pubDate) : undefined;
      if (!occurredAt || Number.isNaN(occurredAt.getTime())) continue;

      events.push({
        countryCode: "PT",
        sourceRecordId: item.guid,
        sourceType: "news",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        occurredAt: occurredAt.toISOString(),
        publishedAt: occurredAt.toISOString(),
        geoPrecision: "MUNICIPALITY",
        locationConfidence: municipalityLocationConfidence,
        district: concelho,
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
