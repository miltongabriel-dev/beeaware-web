// BeeAware Brasil roadmap — MetropolesAdapter, a national News
// Intelligence source with a real editorial focus on policing/crime
// coverage. Feed: https://www.metropoles.com/feed (verified live
// 2026-08-29, standard RSS 2.0, no auth, 20 real <item> entries, unique
// per-article <guid> — no CNN-Brasil-style broken-guid issue here).
// Location detection has no per-article structural signal to key off —
// see national_pt_news.ts's own header for the shared findState()-then-
// findCity() approach.

import { parseFeedItems } from "../../rss.ts";
import { eventsFromNationalPtBrItems } from "./national_pt_news.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const FEED_URL = "https://www.metropoles.com/feed";

export class MetropolesAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      name: "Metrópoles",
      organisation: "Metrópoles",
      sourceType: "news",
      sourceUrl: FEED_URL,
      adapterName: "MetropolesAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "every 4 hours",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(FEED_URL);
    if (!res.ok) {
      throw new Error(`Metrópoles feed request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "metropoles-feed",
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
