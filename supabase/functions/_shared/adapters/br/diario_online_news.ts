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
import { parseFeedItems, type RssFeedItem } from "../../rss.ts";
import { findCity, findState, getMunicipiosForUf, prefetchMunicipios } from "./geo_text_match.ts";
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

    interface Candidate {
      item: RssFeedItem;
      eventCategory: string;
      eventType: string;
      severity: string;
      occurredAt: Date;
      normalizedText: string;
      fallbackUf?: string;
    }

    // First pass: classify, and run findState() (pure regex, no IBGE
    // call) up front for every item — purely to learn, before any
    // network call, the full SET of states this pull could possibly
    // need. This feed is NOT Pará-only (see header) and can mix in
    // any of the other 26 states across its ~100 items; visiting them
    // in feed order and fetching each newly-seen state's municipios
    // one at a time (the old behaviour) is what made this adapter's
    // scheduled runs consistently exceed the Edge Function's ~150s
    // limit (confirmed live 2026-11-02, same root cause as
    // G1NewsAdapter's — see that adapter's own fix and
    // geo_text_match.ts's comment). Collecting the full set first lets
    // every municipios fetch below go out concurrently instead.
    const candidates: Candidate[] = [];
    const neededUfs = new Set<string>(["PA"]);
    for (const item of items) {
      const mapped = classifyPtBrNews(item.title, item.subtitle);
      if (!mapped) continue;
      const [eventCategory, eventType, severity] = mapped;

      const occurredAt = item.pubDate ? new Date(item.pubDate) : undefined;
      if (!occurredAt || Number.isNaN(occurredAt.getTime())) continue;

      const normalizedText = stripAccentsLower(`${item.title} ${item.subtitle}`);
      const fallbackUf = findState(normalizedText);
      if (fallbackUf) neededUfs.add(fallbackUf);
      candidates.push({ item, eventCategory, eventType, severity, occurredAt, normalizedText, fallbackUf });
    }

    await prefetchMunicipios([...neededUfs]);

    const events: SecurityEvent[] = [];
    for (const c of candidates) {
      // Pará first (this outlet's own home turf, most likely to be
      // named only by city — see header), then the generic detector.
      let uf = "PA";
      let city = findCity(c.normalizedText, await getMunicipiosForUf("PA"));
      if (!city) {
        if (!c.fallbackUf) continue; // no location signal at all — skip, same as every other adapter here.
        uf = c.fallbackUf;
        city = findCity(c.normalizedText, await getMunicipiosForUf(uf));
      }

      const geoPrecision = city ? "MUNICIPALITY" : "STATE";
      const locationConfidence = city ? municipalityLocationConfidence : stateLocationConfidence;

      events.push({
        countryCode: "BR",
        stateCode: uf,
        sourceRecordId: c.item.guid,
        sourceType: "news",
        eventCategory: c.eventCategory as SecurityEvent["eventCategory"],
        eventType: c.eventType,
        occurredAt: c.occurredAt.toISOString(),
        publishedAt: c.occurredAt.toISOString(),
        geoPrecision,
        locationConfidence,
        state: uf,
        city: city?.nome,
        cityIbgeCode: city ? String(city.id) : undefined,
        occurrenceCount: 1,
        severity: c.severity,
        confidenceScore: computeConfidenceScore({
          reliabilityGrade: "established_local_journalism",
          locationConfidence,
        }),
        rawPayload: {
          title: c.item.title,
          subtitle: truncateForDisplay(c.item.subtitle),
          link: c.item.link,
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
