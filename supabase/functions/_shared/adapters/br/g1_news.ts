// BeeAware Brasil roadmap / Phase 6 — G1NewsAdapter, the project's first
// News Intelligence source (roadmap 5.1/11.7). Everything else in this
// project ingests official statistics; this is the first "news → is this
// really an incident? → event" pipeline, and the first source to ever use
// geoPrecision STATE and sourceType "news".
//
// v2 (2026-08-29): one feed PER STATE, not the single national front
// page. g1.globo.com/rss/g1/{uf}/{uf-slug}/ — every one of the 27
// verified live 2026-08-29 (all responded 200 with 80-100 real <item>
// entries). The single national feed (g1.globo.com/rss/g1/) spreads the
// same ~100 items across all 27 states and can (confirmed live: Pará
// had zero classifiable items across this adapter's first two days)
// miss a state entirely in a given pull. 27 separate feeds instead
// multiplies real per-state coverage roughly ~20x, and crucially each
// state's own regional feed uses the exact same
// /{uf}/{region-slug}/noticia/... article URL shape as the old national
// feed (confirmed live against the PA feed) — so ufFromLink/findCity
// below needed no change at all, only fetch() changed shape.
//
// Location comes from the article's OWN URL, not text extraction: every
// G1 regional article's link is shaped
// https://g1.globo.com/{uf}/{region-slug}/noticia/.../slug.ghtml — e.g.
// g1.globo.com/al/alagoas/noticia/... or g1.globo.com/sp/sao-jose-do-rio-
// preto-aracatuba/noticia/.... The 2-letter path segment is a real,
// reliable Brazilian UF code (VALID_UFS below), so state-level geocoding
// is free and exact. region-slug is NOT used for city-level precision:
// many slugs cover several municipalities at once (São Paulo's "são
// josé do rio preto e araçatuba" is one regional bureau's coverage area,
// not a single city), so guessing a municipality from it would invent
// precision this source doesn't actually have. Articles whose link has
// no 2-letter UF segment (politics/economy/world desks) are skipped
// entirely.
//
// Classifier (roadmap 5.2's "is_event / content_type" distinction) now
// lives in pt_news_classifier.ts, shared with every other Portuguese
// news adapter this project has — see that file's own header for the
// known, accepted false-negative/false-positive trade-offs.
//
// occurredAt uses the article's own pubDate (when G1 published it), not
// an extracted "when did this happen" from the body text — pubDate is
// what every news-based system reaches for first, and is honestly
// labelled here as an approximation via this adapter's confidence_score,
// not presented as a resolved incident timestamp.
//
// City tier: G1 headlines often DO name the city directly ("Homem é
// preso suspeito de matar mulher em Caruaru") even though the URL's
// region-slug can't be trusted for it (see above). This matches the
// title+subtitle against the REAL list of municipality names for the
// already-known UF (geo_text_match.ts's findCity, backed by IBGE's own
// endpoint — same one IbgeAdapter uses). A miss falls back to the STATE
// tier — additive, never a regression.

import { classifyPtBrNews, stripAccentsLower } from "./pt_news_classifier.ts";
import { decodeXmlBytes, parseFeedItems } from "../../rss.ts";
import { fetchMunicipiosForUf, findCity, IbgeMunicipio } from "./geo_text_match.ts";
import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const VALID_UFS = new Set([
  "AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA", "MT", "MS",
  "MG", "PA", "PB", "PR", "PE", "PI", "RJ", "RN", "RS", "RO", "RR", "SC",
  "SP", "SE", "TO",
]);

// UF -> G1's own regional-portal slug (the URL segment after
// /rss/g1/{uf}/). All 27 verified live 2026-08-29.
const UF_SLUGS: Record<string, string> = {
  AC: "acre", AL: "alagoas", AP: "amapa", AM: "amazonas", BA: "bahia",
  CE: "ceara", DF: "distrito-federal", ES: "espirito-santo", GO: "goias",
  MA: "maranhao", MT: "mato-grosso", MS: "mato-grosso-do-sul",
  MG: "minas-gerais", PA: "para", PB: "paraiba", PR: "parana",
  PE: "pernambuco", PI: "piaui", RJ: "rio-de-janeiro",
  RN: "rio-grande-do-norte", RS: "rio-grande-do-sul", RO: "rondonia",
  RR: "roraima", SC: "santa-catarina", SP: "sao-paulo", SE: "sergipe",
  TO: "tocantins",
};

function feedUrlForUf(uf: string): string {
  return `https://g1.globo.com/rss/g1/${uf.toLowerCase()}/${UF_SLUGS[uf]}/`;
}

// /{uf}/{region-slug}/noticia/... — region-slug itself isn't used for
// anything beyond confirming this is a real regional article (as
// opposed to /politica/, /economia/, /mundo/, which have no 2-letter
// segment at all and are excluded here, not misread as a UF).
const UF_FROM_LINK_RE = /^https:\/\/g1\.globo\.com\/([a-z]{2})\//;

function ufFromLink(link: string): string | undefined {
  const match = UF_FROM_LINK_RE.exec(link);
  if (!match) return undefined;
  const uf = match[1].toUpperCase();
  return VALID_UFS.has(uf) ? uf : undefined;
}

export class G1NewsAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      name: "G1 - Feeds Estaduais",
      organisation: "Globo Comunicação e Participações S.A.",
      sourceType: "news",
      sourceUrl: "https://g1.globo.com/rss/g1/{uf}/{uf-slug}/",
      adapterName: "G1NewsAdapter",
      adapterVersion: "0.2.0",
      refreshFrequency: "every 4 hours",
    };
  }

  // One record per state's own regional feed (27 total) rather than the
  // single national front-page feed — see header. A state whose feed
  // fails this particular run (network hiccup, G1 changes one URL) is
  // skipped rather than failing the whole adapter — the other 26
  // states' real data shouldn't be held hostage by one flaky fetch,
  // same reasoning as every other per-record failure in this project.
  // Fetched concurrently (Promise.allSettled, not a sequential loop) so
  // 27 real HTTP round trips don't serialize into a multi-tens-of-
  // seconds wall-clock cost on every 4-hourly run.
  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const fetchedAt = new Date().toISOString();
    const settled = await Promise.allSettled(
      Object.keys(UF_SLUGS).map(async (uf) => {
        const res = await fetch(feedUrlForUf(uf));
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const payload = decodeXmlBytes(await res.arrayBuffer());
        return { uf, payload };
      }),
    );

    const records: RawSecurityRecord[] = [];
    for (const result of settled) {
      if (result.status === "fulfilled") {
        records.push({
          sourceRecordId: `g1-feed-${result.value.uf}`,
          payload: result.value.payload,
          fetchedAt,
        });
      } else {
        console.error("G1NewsAdapter: a state feed fetch failed:", result.reason);
      }
    }
    if (records.length === 0) {
      throw new Error("G1NewsAdapter: every state feed failed");
    }
    return records;
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const xml = record.payload as string;
    const items = parseFeedItems(xml, "atom:subtitle");
    const stateLocationConfidence = defaultLocationConfidence("STATE");
    const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");

    // A single state's regional feed overwhelmingly carries that one
    // state's own articles (confirmed live), so this cache typically
    // ends up doing exactly one IBGE fetch per normalize() call — kept
    // as a map (not a single value) purely to stay correct on the rare
    // cross-linked item from a different UF, at no extra cost in the
    // common case. A failed IBGE fetch for one UF just degrades that
    // UF's articles back to the STATE tier rather than failing the run.
    const municipiosByUf = new Map<string, IbgeMunicipio[]>();
    async function municipiosFor(uf: string): Promise<IbgeMunicipio[]> {
      const cached = municipiosByUf.get(uf);
      if (cached) return cached;
      let list: IbgeMunicipio[];
      try {
        list = await fetchMunicipiosForUf(uf);
      } catch (e) {
        console.error(`G1NewsAdapter: municipios fetch failed for ${uf}:`, e);
        list = [];
      }
      municipiosByUf.set(uf, list);
      return list;
    }

    const events: SecurityEvent[] = [];
    for (const item of items) {
      const uf = ufFromLink(item.link);
      if (!uf) continue;

      const mapped = classifyPtBrNews(item.title, item.subtitle);
      if (!mapped) continue;
      const [eventCategory, eventType, severity] = mapped;

      const occurredAt = item.pubDate ? new Date(item.pubDate) : undefined;
      if (!occurredAt || Number.isNaN(occurredAt.getTime())) continue;

      const normalizedText = stripAccentsLower(`${item.title} ${item.subtitle}`);
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
        // No dedicated "headline"/"article link" column exists on
        // security_events — every other adapter's original_category
        // holds a source-side TAXONOMY label, which a headline isn't,
        // so it's kept here instead. This is what lets a consuming RPC
        // show a real article to link out to.
        rawPayload: { title: item.title, subtitle: item.subtitle, link: item.link },
      });
    }
    return events;
  }

  // Checks São Paulo's own feed (the largest state feed) as a single
  // representative proxy for "is G1's regional RSS system up" — fetch()
  // already hits all 27 feeds every real run; re-checking all 27 here
  // too would double the request count for a health ping that's really
  // asking one binary question. If G1 breaks this URL scheme, SP breaks
  // with it.
  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(feedUrlForUf("SP"));
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on SP feed` };
      }
      const xml = decodeXmlBytes(await res.arrayBuffer());
      const items = parseFeedItems(xml, "atom:subtitle");
      if (items.length === 0) {
        return { status: "RED", message: "No <item> entries found on SP feed — feed markup may have changed" };
      }
      return { status: "GREEN", lastDataDate: new Date().toISOString().slice(0, 10) };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
