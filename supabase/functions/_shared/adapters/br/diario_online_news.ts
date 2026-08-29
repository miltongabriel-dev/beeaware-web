// BeeAware Brasil roadmap — DiarioOnlineAdapter, a Pará/Amazônia-focused
// News Intelligence source, independent of the Globo group (G1) — real
// corroboration value for exactly the region (Pará) whose G1 coverage
// can (confirmed live, see g1_news.ts's own header) miss a given day
// entirely.
//
// Feed: https://www.diarioonline.com.br/feed (verified live 2026-08-29,
// no auth, real RSS 2.0, 100 <item> entries). DOL self-describes as
// "Maior portal de notícias da Amazônia" scoped to "Belém do Pará,
// Região Norte, Amazônia e do mundo" (its own <meta name="description">)
// — but its general /feed is NOT Pará-only: verified live, the same
// pull mixed a Flávio Bolsonaro national-politics story and Paraná
// (PR) news alongside genuine Belém/Pará crime items. So, unlike
// treating every row as PA, this adapter runs the SAME per-article
// location detection the national portals below use — with one twist
// specific to this outlet: Pará municipality names are tried FIRST,
// before the generic state-name detector, because DOL's own local
// stories routinely name a Pará city without ever saying the word
// "Pará" at all (found live: "Jovem é executado em estabelecimento na
// cidade de Altamira" and "Polícia prende sexto suspeito de roubar
// joalheria em Belém" name real Pará municipalities — Altamira, Belém —
// with no state name anywhere in the text; a generic state-name-first
// approach would have missed both and fallen through to the generic
// national-portal skip). Only once no Pará municipality matches does
// this fall back to the generic findState() detector (catches DOL's own
// non-Pará stories, e.g. a real Paraná item found live in the same
// pull — "Mulher pede socorro em prontuário no Paraná..." — correctly
// distinguished from Pará since "parana" and "para" don't collide after
// accent-stripping, see geo_text_match.ts's own header) with the same
// state-scoped municipality match G1 uses. No signal at all -> skipped,
// same conservative posture as every other adapter here.
//
// item.description here is the article's FULL body text (verified
// live — several paragraphs, not a short subtitle like G1/BBC), which
// is genuinely useful for classification (more real keyword surface)
// but too long to show as a UI subtitle line — truncated in rawPayload
// for that reason (classification still runs on the untruncated text).

import { classifyPtBrNews, stripAccentsLower } from "./pt_news_classifier.ts";
import { parseFeedItems } from "../../rss.ts";
import { fetchMunicipiosForUf, findCity, findState, IbgeMunicipio } from "./geo_text_match.ts";
import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const FEED_URL = "https://www.diarioonline.com.br/feed";

// UI subtitle only — classification always runs on the full text.
const SUBTITLE_DISPLAY_LIMIT = 220;
function truncateForDisplay(text: string): string {
  if (text.length <= SUBTITLE_DISPLAY_LIMIT) return text;
  return text.slice(0, SUBTITLE_DISPLAY_LIMIT).trimEnd() + "…";
}

export class DiarioOnlineAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      name: "Diário Online (DOL)",
      organisation: "Diário Online",
      sourceType: "news",
      sourceUrl: FEED_URL,
      adapterName: "DiarioOnlineAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "every 4 hours",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(FEED_URL);
    if (!res.ok) {
      throw new Error(`Diário Online feed request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "diario-online-feed",
        payload: await res.text(),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const xml = record.payload as string;
    const items = parseFeedItems(xml);
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
        console.error(`DiarioOnlineAdapter: municipios fetch failed for ${uf}:`, e);
        list = [];
      }
      municipiosByUf.set(uf, list);
      return list;
    }

    const events: SecurityEvent[] = [];
    for (const item of items) {
      const mapped = classifyPtBrNews(item.title, item.subtitle);
      if (!mapped) continue;
      const [eventCategory, eventType, severity] = mapped;

      const occurredAt = item.pubDate ? new Date(item.pubDate) : undefined;
      if (!occurredAt || Number.isNaN(occurredAt.getTime())) continue;

      const normalizedText = stripAccentsLower(`${item.title} ${item.subtitle}`);

      // Pará first (this outlet's own home turf, most likely to be
      // named only by city — see header), then the generic detector.
      let uf: string | undefined = "PA";
      let city = findCity(normalizedText, await municipiosFor("PA"));
      if (!city) {
        uf = findState(normalizedText);
        if (!uf) continue; // no location signal at all — skip, same as every other adapter here.
        city = findCity(normalizedText, await municipiosFor(uf));
      }

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
        rawPayload: {
          title: item.title,
          subtitle: truncateForDisplay(item.subtitle),
          link: item.link,
        },
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
