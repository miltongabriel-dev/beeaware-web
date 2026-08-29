// BeeAware Brasil roadmap — shared normalize() body for Portuguese-
// language NATIONAL news portals with no structural per-article
// location signal (CNN Brasil, Metrópoles, UOL, Agência Brasil, Folha —
// unlike G1, whose article URL always embeds a real UF, or Diário
// Online, whose own regional focus lets Pará be tried first before this
// generic path). Every one of these determines location the same way:
// classify the text, try to name a state directly (geo_text_match.ts's
// findState), then a municipality within that state — skip entirely
// when no state can be named. An unlocalizable item from a national
// portal has nothing useful to add over one that's provably somewhere
// in Brazil but nowhere specific (this project doesn't have a BR-wide
// COUNTRY-level display path the way it does for BBC/GB — see
// nearby_news's own SQL — so a state-less BR row would just be
// invisible in the feed, not a softer fallback; skipping is honest
// about that rather than writing a row nothing will ever show).
//
// pubDate is parsed with parsePossiblyPtBrDate (rss.ts) rather than a
// bare `new Date()` for all five, not just UOL (the one verified to
// need it) — it already tries plain Date parsing first and only
// applies the Portuguese-locale rewrite as a fallback, so it's a safe
// superset for portals that don't need the rewrite.

import { classifyPtBrNews, stripAccentsLower } from "./pt_news_classifier.ts";
import { parsePossiblyPtBrDate, stripHtmlTags, type RssFeedItem } from "../../rss.ts";
import { fetchMunicipiosForUf, findCity, findState, IbgeMunicipio } from "./geo_text_match.ts";
import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type { SecurityEvent } from "../types.ts";

export async function eventsFromNationalPtBrItems(items: RssFeedItem[]): Promise<SecurityEvent[]> {
  const stateLocationConfidence = defaultLocationConfidence("STATE");
  const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");
  const municipiosByUf = new Map<string, IbgeMunicipio[]>();

  async function municipiosFor(uf: string): Promise<IbgeMunicipio[]> {
    const cached = municipiosByUf.get(uf);
    if (cached) return cached;
    let list: IbgeMunicipio[];
    try {
      list = await fetchMunicipiosForUf(uf);
    } catch (e) {
      console.error(`national_pt_news: municipios fetch failed for ${uf}:`, e);
      list = [];
    }
    municipiosByUf.set(uf, list);
    return list;
  }

  const events: SecurityEvent[] = [];
  for (const item of items) {
    const subtitle = stripHtmlTags(item.subtitle);
    const mapped = classifyPtBrNews(item.title, subtitle);
    if (!mapped) continue;
    const [eventCategory, eventType, severity] = mapped;

    const occurredAt = item.pubDate ? parsePossiblyPtBrDate(item.pubDate) : undefined;
    if (!occurredAt) continue;

    const normalizedText = stripAccentsLower(`${item.title} ${subtitle}`);
    const uf = findState(normalizedText);
    if (!uf) continue;
    const city = findCity(normalizedText, await municipiosFor(uf));
    const geoPrecision = city ? "MUNICIPALITY" : "STATE";
    const locationConfidence = city ? municipalityLocationConfidence : stateLocationConfidence;

    events.push({
      countryCode: "BR",
      stateCode: uf,
      sourceRecordId: item.guid,
      sourceType: "news",
      eventCategory: eventCategory as SecurityEvent["eventCategory"],
      eventType,
      occurredAt: occurredAt.toISOString(),
      publishedAt: occurredAt.toISOString(),
      geoPrecision,
      locationConfidence,
      state: uf,
      city: city?.nome,
      cityIbgeCode: city ? String(city.id) : undefined,
      occurrenceCount: 1,
      severity,
      confidenceScore: computeConfidenceScore({
        reliabilityGrade: "established_local_journalism",
        locationConfidence,
      }),
      rawPayload: { title: item.title, subtitle, link: item.link },
    });
  }
  return events;
}
