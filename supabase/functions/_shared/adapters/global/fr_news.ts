// BeeAware Global blueprint — FrNewsAdapter, France's first News
// Intelligence source. bbc_news.ts/pt_news.ts/es_news.ts are the direct
// model for this file's shape.
//
// Investigated live (2026-09-07): France has no equivalent of
// data.police.uk (which already gives UK/Northern Ireland real pins for
// free), so without this adapter France would only ever get the
// département choropleth (fr_crime.ts), never a single pin.
// https://actu17.fr/feed/ — "L'actualité police, justice, faits divers
// en continu" ("La sécurité commence par l'information") — is a
// dedicated police/justice/faits-divers outlet, the closest French
// equivalent to La Vanguardia's "Sucesos" section that es_news.ts uses.
// A real live pull found genuine `<category>` values of "Faits-Divers"
// and "Justice" (both kept) alongside "International" (excluded below —
// this feed isn't scoped to France only, same reasoning as
// NON_SPAIN_CATEGORIES on es_news.ts). `pubDate` is standard RFC822
// English-language format — no special month-name parsing needed
// (unlike some Brazilian portuguese-language feeds).
//
// Département matching uses findAreaName (geo_text_match_generic.ts)
// against fr_crime.ts's own DEPARTEMENT_NAME list (all 101 names). Real
// live items confirmed French crime journalism routinely names the
// département directly ("Saône-et-Loire", "Doubs" both appeared in
// titles/descriptions in the same live pull, with no city-level
// fallback needed) — but an item naming only a city/commune with no
// département mention (also seen live: "Lormont", a Bordeaux-area
// commune, with no "Gironde" anywhere in the text) is skipped rather
// than given an invented precision, same rule pt_news.ts/es_news.ts
// already apply.

import { classifyFrNews } from "./fr_news_classifier.ts";
import { parseFeedItems } from "../../rss.ts";
import { findAreaName, stripAccentsLower } from "./geo_text_match_generic.ts";
import { DEPARTEMENT_NAME } from "./fr_crime.ts";
import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const FEED_URL = "https://actu17.fr/feed/";
const DEPARTEMENT_NAMES = Object.values(DEPARTEMENT_NAME);

// Category confirmed live to mean "not actually about France" — see
// file header. Checked case-sensitively against the exact tag text this
// feed uses.
const NON_FRANCE_CATEGORIES = new Set(["International"]);

export class FrNewsAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "FR",
      name: "Actu17 — Police, Justice, Faits-Divers",
      organisation: "Actu17",
      sourceType: "news",
      sourceUrl: FEED_URL,
      adapterName: "FrNewsAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "every 4 hours",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(FEED_URL);
    if (!res.ok) {
      throw new Error(`Actu17 feed request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "actu17-feed",
        payload: await res.text(),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const xml = record.payload as string;
    const items = parseFeedItems(xml);
    const departmentLocationConfidence = defaultLocationConfidence("DISTRICT");

    const events: SecurityEvent[] = [];
    for (const item of items) {
      if (item.category && NON_FRANCE_CATEGORIES.has(item.category)) continue;

      const mapped = classifyFrNews(item.title, item.subtitle);
      if (!mapped) continue;
      const [eventCategory, eventType, severity] = mapped;

      const departement = findAreaName(
        stripAccentsLower(`${item.title} ${item.subtitle}`),
        DEPARTEMENT_NAMES,
      );
      if (!departement) continue;

      const occurredAt = item.pubDate ? new Date(item.pubDate) : undefined;
      if (!occurredAt || Number.isNaN(occurredAt.getTime())) continue;

      events.push({
        countryCode: "FR",
        sourceRecordId: item.guid,
        sourceType: "news",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        occurredAt: occurredAt.toISOString(),
        publishedAt: occurredAt.toISOString(),
        geoPrecision: "DISTRICT",
        locationConfidence: departmentLocationConfidence,
        district: departement,
        occurrenceCount: 1,
        severity,
        confidenceScore: computeConfidenceScore({
          reliabilityGrade: "established_local_journalism",
          locationConfidence: departmentLocationConfidence,
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
