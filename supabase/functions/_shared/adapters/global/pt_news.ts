// BeeAware Global blueprint — PtNewsAdapter, Portugal's first News
// Intelligence source. bbc_news.ts is the direct model for this file's
// shape; g1_news.ts's own header has the fuller "known, accepted failure
// modes" rationale this and every other news adapter in this project
// shares.
//
// Investigated live (2026-09-01): RTP Notícias' "País" (national) feed —
// https://www.rtp.pt/noticias/rss/pais — is a plain, unauthenticated RSS
// 2.0 feed, no key needed. A real 50-item pull found 3 genuine crime/
// accident items, each with a concelho name already embedded in its own
// title ("...em Ansião (Leiria)", "...em Algés") — the same real-world
// hit rate G1/BBC already run in production on.
//
// classifyPtBrNews (adapters/br/pt_news_classifier.ts) is reused as-is
// rather than duplicated: its KEYWORD_MAP vocabulary (homicídio, assalto,
// furto, roubo, tiroteio, incêndio, acidente...) is standard Portuguese,
// not Brazilian slang — nothing in it needed changing for European
// Portuguese. Concelho matching uses findAreaName
// (geo_text_match_generic.ts) against pt_crime.ts's own CONCELHO_NAME
// list (all 308 names) — an item with no concelho match is skipped
// rather than given an invented precision, same rule national_pt_news.ts
// already applies to Brazil's own no-structural-signal portals.
//
// Unlike G1's per-article location signal (a Brazilian state code baked
// into the URL), RTP's article URL/markup carries no structural location
// at all — text matching is the only option here, same as Brazil's
// national portals.

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

const FEED_URL = "https://www.rtp.pt/noticias/rss/pais";
const CONCELHO_NAMES = Object.values(CONCELHO_NAME);

export class PtNewsAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "PT",
      name: "RTP Notícias — País",
      organisation: "Rádio e Televisão de Portugal",
      sourceType: "news",
      sourceUrl: FEED_URL,
      adapterName: "PtNewsAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "every 4 hours",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(FEED_URL);
    if (!res.ok) {
      throw new Error(`RTP feed request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "rtp-pais-feed",
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
