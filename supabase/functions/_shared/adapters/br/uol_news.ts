// BeeAware Brasil roadmap — UolAdapter, a national News Intelligence
// source. Feed: https://rss.uol.com.br/feed/noticias.xml (verified live
// 2026-08-29, no auth, real RSS 2.0, 15 <item> entries — a smaller feed
// than the others tested, still real). Location detection has no
// per-article structural signal — see national_pt_news.ts's own header
// for the shared findState()-then-findCity() approach.
//
// Two real encoding/format quirks found live here, both handled by
// shared helpers rather than one-off code in this file:
//   - The feed is ISO-8859-1, declared only via the HTTP response's own
//     Content-Type header (charset=ISO-8859-1) — NOT in the XML prolog
//     the way Folha declares it. decodeXmlBytes (rss.ts) checks the
//     Content-Type header first for exactly this reason.
//   - pubDate uses Portuguese weekday/month abbreviations ("Sáb, 29 Ago
//     2026 08:14:25 -0300"), which `new Date()` can't parse at all
//     (Invalid Date) — parsePossiblyPtBrDate (rss.ts) handles this.

import { decodeXmlBytes, parseFeedItems } from "../../rss.ts";
import { eventsFromNationalPtBrItems } from "./national_pt_news.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const FEED_URL = "https://rss.uol.com.br/feed/noticias.xml";

async function fetchAndDecode(): Promise<{ ok: boolean; status: number; xml: string }> {
  const res = await fetch(FEED_URL);
  const xml = decodeXmlBytes(await res.arrayBuffer(), res.headers.get("content-type"));
  return { ok: res.ok, status: res.status, xml };
}

export class UolAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      name: "UOL Notícias",
      organisation: "UOL",
      sourceType: "news",
      sourceUrl: FEED_URL,
      adapterName: "UolAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "every 4 hours",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const { ok, status, xml } = await fetchAndDecode();
    if (!ok) {
      throw new Error(`UOL feed request failed: ${status}`);
    }
    return [
      {
        sourceRecordId: "uol-feed",
        payload: xml,
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const xml = record.payload as string;
    return eventsFromNationalPtBrItems(parseFeedItems(xml));
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const { ok, status, xml } = await fetchAndDecode();
      if (!ok) {
        return { status: "RED", message: `HTTP ${status} on feed` };
      }
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
