// BeeAware Brasil roadmap / Phase 6 — G1NewsAdapter, the project's first
// News Intelligence source (roadmap 5.1/11.7). Everything else in this
// project ingests official statistics; this is the first "news → is this
// really an incident? → event" pipeline, and the first source to ever use
// geoPrecision STATE (defaultLocationConfidence already had a STATE tier
// in confidence.ts, unused until now) and sourceType "news".
//
// Feed: https://g1.globo.com/rss/g1/ (no auth, no browser-UA gate,
// verified live 2026-08-27). This is G1's NATIONAL front-page feed, not a
// single state/category feed — checked live: /rss/g1/policia and
// /rss/g1/seguranca both 200 but return an empty <channel> (no <item>
// elements at all — G1 has no dedicated crime/security RSS category), so
// there's no narrower official feed to prefer. The national feed already
// spans nearly every state on its own: a real pull of its 100 items
// covered 26 of Brazil's 27 UFs in one fetch. That's the actual source of
// this adapter's geographic coverage — not per-state feed management.
//
// Location comes from the article's OWN URL, not text extraction: every
// G1 regional article's link is shaped
// https://g1.globo.com/{uf}/{region-slug}/noticia/.../slug.ghtml — e.g.
// g1.globo.com/al/alagoas/noticia/... or g1.globo.com/sp/sao-jose-do-rio-
// preto-aracatuba/noticia/.... The 2-letter path segment is a real,
// reliable Brazilian UF code (VALID_UFS below), so state-level geocoding
// is free and exact — no address/NLP extraction needed for this tier.
// region-slug is NOT used for city-level precision: many slugs cover
// several municipalities at once (see the São Paulo example above,
// "são josé do rio preto e araçatuba" is one regional bureau's coverage
// area, not a single city), so guessing a municipality from it would
// invent precision this source doesn't actually have. Articles whose link
// has no 2-letter UF segment (politics/economy/world desks, ~11% of the
// feed) are skipped entirely — a safety-incident classifier has nothing
// useful to say about an unlocalized national politics story, and forcing
// a COUNTRY-level event onto it would mostly just be noise.
//
// Classifier (roadmap 5.2's "is_event / content_type" distinction) is
// title+subtitle keyword matching, same allowlist philosophy as every
// state adapter's NATUREZA_MAP here — deliberately not exhaustive, and
// deliberately not asked to resolve every ambiguous case. Two known,
// accepted failure modes for this v1 (no LLM classification in this
// project yet — see this adapter's own commit for the product decision):
//   - False negative: a genuine incident whose headline doesn't use any
//     listed keyword (e.g. a headline built entirely around a victim's
//     name) is silently skipped, same as an adapter skipping an
//     unmapped NATUREZA value.
//   - False positive: EXCLUSION_KEYWORDS filters out the clearest
//     statistical/retrospective framing (roadmap 5.2's own worked
//     example, "Roubo cai 18% no Pará em 2026" — matches "roubo" but
//     also "cai", so it's dropped), but a differently-worded statistics
//     piece could still slip through uncaught.
// Both are accuracy trade-offs to revisit if/when this project adds real
// article classification, not bugs in this implementation.
//
// occurredAt uses the article's own pubDate (when G1 published it), not
// an extracted "when did this happen" from the body text — the roadmap's
// pipeline sketch includes a dedicated time-extraction step this v1
// doesn't attempt; pubDate is what every news-based system reaches for
// first, and is honestly labelled here as an approximation via this
// adapter's low confidence_score (news × STATE-precision), not presented
// as a resolved incident timestamp.
//
// City tier (added after the STATE-only v1 above): G1 headlines often DO
// name the city directly ("Homem é preso suspeito de matar mulher em
// Caruaru", "Acidente na BR-232 deixa feridos em Vitória de Santo
// Antão") even though the URL's region-slug can't be trusted for it (see
// above). Rather than attempt free-text street/address extraction — no
// street-level gazetteer exists in this project, and geocoding an
// arbitrary headline fragment would be a real, separate, unreliable
// project (see fetchMunicipiosForUf's own comment) — this matches the
// title+subtitle against the REAL list of municipality names for the
// already-known UF (IbgeAdapter's own endpoint, ibge.ts, proven live).
// Bounding the candidate list to one state first is what makes this
// precise enough to trust: a national list of ~5,570 municipality names
// would produce far more coincidental word matches ("Bom Jesus", "Boa
// Vista", generic-sounding real city names) than the ~15-850 names that
// actually belong to the UF already pinned down by the article's own
// URL. A miss (no known municipality name appears in the text — the
// common case; most headlines only imply location via the region-slug)
// falls back to the STATE tier exactly as before — this is additive,
// never a regression from v1's behaviour.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const FEED_URL = "https://g1.globo.com/rss/g1/";

const VALID_UFS = new Set([
  "AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA", "MT", "MS",
  "MG", "PA", "PB", "PR", "PE", "PI", "RJ", "RN", "RS", "RO", "RR", "SC",
  "SP", "SE", "TO",
]);

interface FeedItem {
  title: string;
  subtitle: string;
  link: string;
  guid: string;
  pubDate?: string;
}

function decodeXmlEntities(text: string): string {
  return text
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .trim();
}

function extractTag(itemXml: string, tag: string): string | undefined {
  const cdataMatch = new RegExp(`<${tag}[^>]*>\\s*<!\\[CDATA\\[(.*?)\\]\\]>\\s*</${tag}>`, "s").exec(itemXml);
  if (cdataMatch) return decodeXmlEntities(cdataMatch[1]);
  const plainMatch = new RegExp(`<${tag}[^>]*>(.*?)</${tag}>`, "s").exec(itemXml);
  return plainMatch ? decodeXmlEntities(plainMatch[1]) : undefined;
}

function parseFeedItems(xml: string): FeedItem[] {
  const items: FeedItem[] = [];
  const itemRe = /<item>(.*?)<\/item>/gs;
  let match: RegExpExecArray | null;
  while ((match = itemRe.exec(xml))) {
    const itemXml = match[1];
    const title = extractTag(itemXml, "title");
    const link = extractTag(itemXml, "link");
    const guid = extractTag(itemXml, "guid") ?? link;
    if (!title || !link || !guid) continue;
    items.push({
      title,
      subtitle: extractTag(itemXml, "atom:subtitle") ?? "",
      link,
      guid,
      pubDate: extractTag(itemXml, "pubDate"),
    });
  }
  return items;
}

// /{uf}/{region-slug}/noticia/... — see header comment for why region-slug
// itself isn't used for anything beyond confirming this is a real regional
// article (as opposed to /politica/, /economia/, /mundo/, which have no
// 2-letter segment at all and are excluded here, not misread as a UF).
const UF_FROM_LINK_RE = /^https:\/\/g1\.globo\.com\/([a-z]{2})\//;

function ufFromLink(link: string): string | undefined {
  const match = UF_FROM_LINK_RE.exec(link);
  if (!match) return undefined;
  const uf = match[1].toUpperCase();
  return VALID_UFS.has(uf) ? uf : undefined;
}

function stripAccentsLower(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

interface IbgeMunicipio {
  id: number;
  nome: string;
}

// Same endpoint IbgeAdapter's own fetch() uses (ibge.ts) — verified live
// there already, one call per UF (not the ~5,570-municipality national
// list, see header comment for why bounding to one state matters for
// match precision).
const IBGE_MUNICIPIOS_URL = "https://servicodados.ibge.gov.br/api/v1/localidades/estados";

async function fetchMunicipiosForUf(uf: string): Promise<IbgeMunicipio[]> {
  const res = await fetch(`${IBGE_MUNICIPIOS_URL}/${uf}/municipios`);
  if (!res.ok) {
    throw new Error(`IBGE municipios request failed for ${uf}: ${res.status}`);
  }
  return await res.json();
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// Longest name first, so a specific match ("boa vista do tupim") is
// tried before a shorter name it happens to contain ("boa vista") —
// otherwise the shorter, wrong municipality would always win. Matched
// with word-boundary anchors (not a bare .includes()) so a short real
// municipality name (e.g. "Una", BA; "Iaçu", BA) can't match inside an
// unrelated longer word.
function findCity(normalizedText: string, municipios: IbgeMunicipio[]): IbgeMunicipio | undefined {
  const sorted = [...municipios].sort((a, b) => b.nome.length - a.nome.length);
  for (const m of sorted) {
    const normalizedName = stripAccentsLower(m.nome);
    const re = new RegExp(`(^|[^a-z0-9])${escapeRegExp(normalizedName)}([^a-z0-9]|$)`);
    if (re.test(normalizedText)) return m;
  }
  return undefined;
}

// keyword -> [eventCategory, eventType, severity]. Checked as substring
// matches against the normalized (lowercase, accent-stripped) title +
// subtitle — same "known, accepted false-negative rate" trade-off as
// every NATUREZA_MAP in this project, see header comment.
// Order matters: classify() returns the FIRST match, so a more specific
// phrase (e.g. "tentativa de latrocínio") must be listed before the
// broader word it contains ("latrocínio") or it would never be reached.
const KEYWORD_MAP: [string, string, string, string][] = [
  ["tentativa de latrocinio", "VIOLENCE", "attempted_homicide", "medium"],
  ["tentativa de homicidio", "VIOLENCE", "attempted_homicide", "medium"],
  ["tentou matar", "VIOLENCE", "attempted_homicide", "medium"],
  ["homicidio", "VIOLENCE", "homicide", "high"],
  ["assassinad", "VIOLENCE", "homicide", "high"],
  ["morre baleado", "VIOLENCE", "homicide", "high"],
  ["morre baleada", "VIOLENCE", "homicide", "high"],
  ["feminicidio", "VIOLENCE", "femicide", "high"],
  ["latrocinio", "VIOLENCE", "homicide", "high"],
  ["estupro", "VIOLENCE", "sexual_violence", "high"],
  ["abuso sexual", "VIOLENCE", "sexual_violence", "high"],
  ["violencia sexual", "VIOLENCE", "sexual_violence", "high"],
  ["violencia domestica", "VIOLENCE", "domestic_violence", "medium"],
  ["sequestr", "VIOLENCE", "kidnapping", "high"],
  ["cativeiro", "VIOLENCE", "kidnapping", "high"],
  ["assalto", "PROPERTY", "robbery", "medium"],
  ["assaltantes", "PROPERTY", "robbery", "medium"],
  ["roubo", "PROPERTY", "robbery", "medium"],
  ["roubad", "PROPERTY", "robbery", "medium"],
  ["furto", "PROPERTY", "theft", "low"],
  ["furtad", "PROPERTY", "theft", "low"],
  ["tiroteio", "PUBLIC_SAFETY", "weapon", "high"],
  ["troca de tiros", "PUBLIC_SAFETY", "weapon", "high"],
  ["baleado", "PUBLIC_SAFETY", "weapon", "high"],
  ["baleada", "PUBLIC_SAFETY", "weapon", "high"],
  ["trafico de drogas", "PUBLIC_SAFETY", "drugs", "medium"],
  ["apreensao de drogas", "PUBLIC_SAFETY", "drugs", "medium"],
  ["traficante", "PUBLIC_SAFETY", "drugs", "medium"],
  ["incendio", "PUBLIC_SAFETY", "fire", "medium"],
  ["capotou", "ROAD_SAFETY", "accident", "medium"],
  ["capotamento", "ROAD_SAFETY", "accident", "medium"],
  ["colisao", "ROAD_SAFETY", "accident", "medium"],
  ["atropelad", "ROAD_SAFETY", "accident", "medium"],
  ["acidente", "ROAD_SAFETY", "accident", "low"],
];

// If any of these also match, the article is framing a STATISTIC,
// political/editorial commentary, or retrospective piece around a crime
// word, not reporting a specific incident (roadmap 5.2's own worked
// example) — skip regardless of which KEYWORD_MAP entry matched. Found
// live: a candidate's stump speech mentioning "roubos de celulares" while
// criticising public safety policy matched "roubo" with nothing else in
// this project's classifiers to tell it apart from a real robbery report
// — "candidato" is a cheap, real signal that this is commentary, not an
// occurrence.
const EXCLUSION_KEYWORDS = [
  "balanco", "estatistica", "levantamento", "pesquisa", "aponta",
  "cai ", "caiu ", "subiu ", "sobe ", "aumenta", "aumento de", "recuo",
  "queda de", "ranking", "comparad", "%", "candidato",
];

// Words indicating a death, checked only to upgrade an already-matched
// road-safety accident to fatal_accident/high — NOT used as a classifier
// trigger on their own. Found live: "encontrado morto"/"encontrada morta"
// were tried as direct VIOLENCE/homicide triggers and immediately produced
// real false positives (a drowning while on holiday, a body found after a
// missing-persons search of unstated cause) — "found dead" describes any
// death discovery, not specifically a homicide, and claiming otherwise is
// exactly the kind of invented precision this project's confidence model
// exists to avoid (see confidence.ts). Not reintroduced even as a lower-
// severity trigger; a real homicide almost always also earns one of the
// unambiguous keywords above (assassinado, baleado, esfaqueado, etc.).
const DEATH_WORDS = ["morreu", "morto", "morta", "morte", "obito"];

// "homicídio CULPOSO" is Brazilian legal language for a death caused by
// negligence (traffic, workplace) — not the doloso (intentional) crime
// this project's "homicide" category means everywhere else (matches how
// mg_ssp.ts's own NATUREZA_MAP only maps "HOMICIDIO CONSUMADO (REGISTROS)",
// SSP-MG's own doloso-only bucket). Found live: a worker fatally struck by
// a garbage truck was reported as "registrado como homicídio culposo" —
// matching this project's plain "homicidio"/"latrocinio" keywords would
// have mislabeled a workplace accident as an intentional violent crime.
function isCulposo(normalized: string): boolean {
  return normalized.includes("culposo");
}

const HOMICIDE_FAMILY_TYPES = new Set(["homicide", "attempted_homicide", "femicide"]);

function classify(title: string, subtitle: string): [string, string, string] | undefined {
  const normalized = stripAccentsLower(`${title} ${subtitle}`);
  if (EXCLUSION_KEYWORDS.some((kw) => normalized.includes(kw))) return undefined;

  const culposo = isCulposo(normalized);
  for (const [keyword, eventCategory, eventType, severity] of KEYWORD_MAP) {
    if (!normalized.includes(keyword)) continue;
    if (culposo && HOMICIDE_FAMILY_TYPES.has(eventType)) continue;

    if (eventType === "accident" && DEATH_WORDS.some((w) => normalized.includes(w))) {
      return [eventCategory, "fatal_accident", "high"];
    }
    return [eventCategory, eventType, severity];
  }
  return undefined;
}

export class G1NewsAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      name: "G1 - Feed Nacional",
      organisation: "Globo Comunicação e Participações S.A.",
      sourceType: "news",
      sourceUrl: FEED_URL,
      adapterName: "G1NewsAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "every 4 hours",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(FEED_URL);
    if (!res.ok) {
      throw new Error(`G1 feed request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "g1-feed",
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

    // Fetched lazily, once per distinct UF actually present in this run
    // (typically a handful, not all 27) — a failed IBGE fetch for one UF
    // just degrades that UF's articles back to the STATE tier rather
    // than failing the whole adapter run (this feed's own fetch() has
    // already succeeded by the time normalize() runs; a second source
    // being flaky shouldn't cost the first source's real data).
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

      const mapped = classify(item.title, item.subtitle);
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
        // security_events — every other adapter's original_category holds
        // a source-side TAXONOMY label (e.g. "HOMICIDIO DOLOSO"), which a
        // headline isn't, so it's kept here instead. This is what lets a
        // consuming RPC show a real article to link out to (roadmap 5.3:
        // "visibly distinguish... independently corroborated events" —
        // a linkable byline is a big part of that for a news source
        // specifically, unlike an aggregate statistic).
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
