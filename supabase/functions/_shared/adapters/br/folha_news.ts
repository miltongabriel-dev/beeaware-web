// BeeAware Brasil roadmap — FolhaAdapter, a national News Intelligence
// source. Feed: https://feeds.folha.uol.com.br/emcimadahora/rss091.xml
// ("Em cima da hora" — Folha de S.Paulo's real-time wire, verified live
// 2026-08-29, no auth, real RSS 0.91, 100 <item> entries — the largest
// single feed found in this project's whole news-source survey).
// Location detection has no per-article structural signal — see
// national_pt_news.ts's own header for the shared findState()-then-
// findCity() approach.
//
// This feed's own XML prolog declares encoding="ISO-8859-1" — verified
// live it genuinely IS Latin-1 (decoding as UTF-8, what a plain
// res.text() always does, produces "Pol�cia" instead of "Polícia").
// decodeXmlBytes (rss.ts) reads that declaration and decodes correctly.
//
// No <guid> tag exists in this feed at all (checked live) — every item
// instead reaches this adapter's sourceRecordId via item.link, which
// parseFeedItems already falls back to when a real <guid> is absent.
// Folha's own link is a redirect URL
// (redir.folha.com.br/redir/online/emcimadahora/rss091/*{real-url}) —
// still unique per article, just not the final destination URL; fine
// for uniqueness, which is all sourceRecordId needs.

import { decodeXmlBytes, parseFeedItems } from "../../rss.ts";
import { eventsFromNationalPtBrItems } from "./national_pt_news.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const FEED_URL = "https://feeds.folha.uol.com.br/emcimadahora/rss091.xml";

export class FolhaAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      name: "Folha de S.Paulo - Em cima da hora",
      organisation: "Folha de S.Paulo",
      sourceType: "news",
      sourceUrl: FEED_URL,
      adapterName: "FolhaAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "every 4 hours",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(FEED_URL);
    if (!res.ok) {
      throw new Error(`Folha feed request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "folha-feed",
        payload: decodeXmlBytes(await res.arrayBuffer(), res.headers.get("content-type")),
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
      const res = await fetch(FEED_URL);
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on feed` };
      }
      const xml = decodeXmlBytes(await res.arrayBuffer(), res.headers.get("content-type"));
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
