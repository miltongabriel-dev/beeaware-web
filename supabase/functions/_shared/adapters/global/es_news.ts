// BeeAware Global blueprint — EsNewsAdapter, Spain's first News
// Intelligence source. bbc_news.ts/pt_news.ts are the direct model for
// this file's shape.
//
// Investigated live (2026-09-01): tried a general national feed first
// (abc.es "España" section) — a real 20-item pull found zero classifiable
// crime items, just municipal/political stories. La Vanguardia's own
// dedicated "Sucesos" (incidents) section —
// https://www.lavanguardia.com/rss/sucesos.xml — is a much better fit: a
// real 100-item pull was almost entirely genuine incidents (assault,
// homicide, fire, hit-and-run, drug trafficking, rescue), each with a
// real Spanish city name in its own title (Lloseta, Cuenca, Málaga,
// Castelldefels, Badalona, Teruel...) and a `<category>` tag naming the
// autonomous community (e.g. "Islas Baleares", "Comunidad Valenciana").
// One `<category>` value found live, "Internacional" (a Cyprus ferry
// sinking), is explicitly excluded below — this feed isn't scoped to
// Spain only, unlike RTP's own "País" tier.
//
// Because this section is already curated to be about incidents (unlike
// a general national feed), es_news_classifier.ts's job here is mostly
// to name the incident TYPE, not to filter noise out of an otherwise
// unrelated feed — EXCLUSION_KEYWORDS is kept for the same statistic/
// retrospective framing risk documented on pt_news_classifier.ts, not
// because this feed is noisy.
//
// Município matching uses findAreaName (geo_text_match_generic.ts)
// against es_crime.ts's own MUNICIPIO_NAME list (all 427 names) — an
// item with no município match is skipped rather than given an invented
// precision, same rule pt_news.ts and Brazil's national portals already
// apply.

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

const FEED_URL = "https://www.lavanguardia.com/rss/sucesos.xml";
const MUNICIPIO_NAMES = Object.values(MUNICIPIO_NAME);

// Categories confirmed live to mean "not actually about Spain" — see
// file header. Checked case-sensitively against the exact tag text this
// feed uses.
const NON_SPAIN_CATEGORIES = new Set(["Internacional"]);

export class EsNewsAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "ES",
      name: "La Vanguardia — Sucesos",
      organisation: "La Vanguardia Ediciones",
      sourceType: "news",
      sourceUrl: FEED_URL,
      adapterName: "EsNewsAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "every 4 hours",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(FEED_URL);
    if (!res.ok) {
      throw new Error(`La Vanguardia feed request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "lavanguardia-sucesos-feed",
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
      if (item.category && NON_SPAIN_CATEGORIES.has(item.category)) continue;

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
