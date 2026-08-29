// BeeAware Brasil roadmap — AgenciaBrasilAdapter, a national News
// Intelligence source — Brazil's official public news agency (EBC,
// government-owned), the highest-reliability-grade Portuguese source in
// this project's news lineup. Feed:
// https://agenciabrasil.ebc.com.br/rss.xml (verified live 2026-08-29, no
// auth, real RSS 2.0, 10 <item> entries — more institutional/policy
// coverage than street-crime reporting, so expect a lower classify()
// hit rate than G1/Metrópoles, not a bug). Location detection has no
// per-article structural signal — see national_pt_news.ts's own header
// for the shared findState()-then-findCity() approach.
//
// <guid> here is Drupal's own format ("1385005 at
// https://agenciabrasil.ebc.com.br") rather than a URL — not a problem:
// it's still a real, unique, stable per-article ID (confirmed live
// across a real pull), and sourceRecordId only needs to be that, never
// a real URL.

import { parseFeedItems } from "../../rss.ts";
import { eventsFromNationalPtBrItems } from "./national_pt_news.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const FEED_URL = "https://agenciabrasil.ebc.com.br/rss.xml";

export class AgenciaBrasilAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      name: "Agência Brasil",
      organisation: "Empresa Brasil de Comunicação (EBC)",
      sourceType: "news",
      sourceUrl: FEED_URL,
      adapterName: "AgenciaBrasilAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "every 4 hours",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(FEED_URL);
    if (!res.ok) {
      throw new Error(`Agência Brasil feed request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "agencia-brasil-feed",
        payload: await res.text(),
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
