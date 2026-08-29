// BeeAware Brasil roadmap — CnnBrasilAdapter, a national News
// Intelligence source. Feed: https://www.cnnbrasil.com.br/feed/
// (verified live 2026-08-29, standard WordPress RSS 2.0, no auth, 60
// real <item> entries). Location detection has no per-article structural
// signal to key off (unlike G1's UF-in-URL) — see national_pt_news.ts's
// own header for the shared findState()-then-findCity() approach every
// portal in this situation uses, and why a state-less item is skipped
// rather than kept at some coarser tier.
//
// item.guid is used as sourceRecordId everywhere else in this project,
// but CNN Brasil's own <guid> is a genuinely broken WordPress template
// that isn't interpolating the article slug — verified live: dozens of
// consecutive DIFFERENT articles all shared the literal guid
// "https://www.cnnbrasil.com.br///" (a few "https://www.cnnbrasil.com.br
// /economia//" for one category, still not unique per article). Using
// it as-is would upsert every article on top of whichever one happened
// to run last under the same broken guid, silently losing the rest.
// item.link IS unique per article (confirmed against the same sample),
// so this overrides guid with link before handing items to the shared
// national-portal normalizer.

import { parseFeedItems } from "../../rss.ts";
import { eventsFromNationalPtBrItems } from "./national_pt_news.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const FEED_URL = "https://www.cnnbrasil.com.br/feed/";

export class CnnBrasilAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      name: "CNN Brasil",
      organisation: "CNN Brasil",
      sourceType: "news",
      sourceUrl: FEED_URL,
      adapterName: "CnnBrasilAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "every 4 hours",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(FEED_URL);
    if (!res.ok) {
      throw new Error(`CNN Brasil feed request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "cnn-brasil-feed",
        payload: await res.text(),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const xml = record.payload as string;
    // See header — CNN Brasil's own <guid> isn't unique per article.
    const items = parseFeedItems(xml).map((item) => ({ ...item, guid: item.link }));
    return eventsFromNationalPtBrItems(items);
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
