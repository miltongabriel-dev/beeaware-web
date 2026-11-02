// BeeAware — free-text Brazilian geography matching for news adapters.
//
// findCity: match article text against the real municipality list for
// an ALREADY-KNOWN state. Bounding the candidate list to one state
// first (rather than the ~5,570-name national list) is what makes this
// precise enough to trust — a national list would produce far more
// coincidental word matches ("Bom Jesus", "Boa Vista", genuinely common-
// sounding real city names) than the ~15-850 names that actually belong
// to one already-known UF. Originally g1_news.ts's own
// fetchMunicipiosForUf/findCity — extracted once a second adapter
// (diario_online_news.ts, Pará-only, its state always known in advance)
// needed the same matcher.
//
// findState: for national portals with NO structural per-article
// location signal (CNN Brasil, Metrópoles, UOL, Agência Brasil, Folha —
// unlike G1, whose article URL always embeds a real UF), tries to name
// the state directly from the 27 full state names. Pará is deliberately
// EXCLUDED from BR_STATE_NAMES: after the same accent-stripping every
// matcher in this project uses, "Pará" becomes "para" — Portuguese's
// single most common preposition ("for"/"to"). Matching it as a state
// name would false-positive on nearly every sentence in the language.
// Every other state name was checked by hand against common Portuguese
// words; "Acre" (also a real, if uncommon, adjective meaning "sour/
// bitter") is kept — genuinely rare in crime/news headline text, an
// accepted low residual risk, unlike "para"'s near-certain collision. An
// article genuinely about Pará from one of these portals still gets
// classified, just without state-level precision — same COUNTRY-tier
// honesty this project already applies anywhere real precision isn't
// available (see confidence.ts).

export interface IbgeMunicipio {
  id: number;
  nome: string;
}

// Same endpoint IbgeAdapter's own fetch() uses (ibge.ts) — verified live
// there already, one call per UF.
const IBGE_MUNICIPIOS_URL = "https://servicodados.ibge.gov.br/api/v1/localidades/estados";

export async function fetchMunicipiosForUf(uf: string): Promise<IbgeMunicipio[]> {
  const res = await fetch(`${IBGE_MUNICIPIOS_URL}/${uf}/municipios`);
  if (!res.ok) {
    throw new Error(`IBGE municipios request failed for ${uf}: ${res.status}`);
  }
  return await res.json();
}

// Module-level cache, shared by every caller in this isolate. Before
// this existed, G1NewsAdapter and DiarioOnlineAdapter each kept their
// OWN per-normalize()-call cache, which only ever helped within a
// single call — G1NewsAdapter normalizes one record per state (27
// calls per run), so that still meant up to 27 sequential, uncached
// real IBGE round trips every single run. Confirmed live 2026-11-02:
// this was the dominant cost behind both adapters' scheduled runs
// consistently exceeding the Edge Function's ~150s hard limit (exact
// same ~150.4-150.9s duration every single cycle — a deterministic
// wall-clock ceiling, not network flakiness). A failed fetch caches an
// empty array rather than retrying on every subsequent call in the
// same run, matching every caller's own prior fallback-to-[] behavior.
const municipiosCache = new Map<string, Promise<IbgeMunicipio[]>>();

export function getMunicipiosForUf(uf: string): Promise<IbgeMunicipio[]> {
  let cached = municipiosCache.get(uf);
  if (!cached) {
    cached = fetchMunicipiosForUf(uf).catch((e) => {
      console.error(`geo_text_match: municipios fetch failed for ${uf}:`, e);
      return [];
    });
    municipiosCache.set(uf, cached);
  }
  return cached;
}

// Fetches several UFs' municipality lists concurrently. The actual
// fix for the sequential-fetch cost above: a caller that knows every
// UF it'll need up front (G1NewsAdapter: all 27, right away) should
// call this before its own per-record loop, so every
// getMunicipiosForUf() call inside that loop is a cache hit against
// an already-in-flight (or resolved) promise instead of a fresh round
// trip.
export async function prefetchMunicipios(ufs: string[]): Promise<void> {
  await Promise.allSettled(ufs.map((uf) => getMunicipiosForUf(uf)));
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function stripAccentsLower(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

// Found live 2026-08-29 against a real UOL item: "...na esquina da Av.
// Melvis Muchiutti com a Av. Paraíba" made findState() report the
// article (genuinely about Ivaiporã, Paraná) as being about Paraíba
// instead — Brazilian street names routinely borrow another state's or
// city's name (Av. Paraíba, Rua Bahia, Av. Goiás are all extremely
// common street-naming conventions), so a bare word-boundary match
// can't tell "the place" from "a street named after the place". Applied
// to BOTH findCity and findState: checked against the same
// already-accent-stripped text these functions already work with, so
// the prefix list only needs the stripped forms ("praca", not "praça").
const STREET_PREFIX_RE =
  /\b(?:av|avenida|r|rua|al|alameda|trav|travessa|rod|rodovia|pca|praca|estr|estrada)\.?\s*$/;

function isPrecededByStreetPrefix(text: string, matchIndex: number): boolean {
  return STREET_PREFIX_RE.test(text.slice(0, matchIndex));
}

// Longest name first, so a specific match ("boa vista do tupim") is
// tried before a shorter name it happens to contain ("boa vista") —
// otherwise the shorter, wrong municipality would always win. Matched
// with word-boundary anchors (not a bare .includes()) so a short real
// municipality name (e.g. "Una", BA; "Iaçu", BA) can't match inside an
// unrelated longer word. Every occurrence of a candidate name is
// checked (not just the first) so a street-prefixed false hit doesn't
// block a real, separate mention of the same name elsewhere in the text.
interface CompiledMunicipio {
  municipio: IbgeMunicipio;
  regex: RegExp;
}

// Keyed on the municipios ARRAY ITSELF (not a UF string) — findCity
// has always taken the array directly, and every caller now gets it
// from getMunicipiosForUf()'s own cache above, so the same array
// instance is reused across every call in a run. Without this, every
// findCity() call re-sorted the full list and rebuilt a fresh RegExp
// per candidate municipality from scratch — for a state like SP (645)
// or MG (853), that's hundreds of regex compilations repeated for
// every classified article, confirmed live 2026-11-02 as the other
// half (alongside the uncached IBGE fetch above) of G1NewsAdapter's
// and DiarioOnlineAdapter's scheduled runs reliably exceeding the Edge
// Function's ~150s limit. A WeakMap lets an array that's no longer
// referenced (a failed/empty fetch result) be garbage-collected
// normally.
const compiledCache = new WeakMap<IbgeMunicipio[], CompiledMunicipio[]>();

function compiledFor(municipios: IbgeMunicipio[]): CompiledMunicipio[] {
  let compiled = compiledCache.get(municipios);
  if (!compiled) {
    compiled = [...municipios]
      .sort((a, b) => b.nome.length - a.nome.length)
      .map((municipio) => ({
        municipio,
        regex: new RegExp(`(^|[^a-z0-9])${escapeRegExp(stripAccentsLower(municipio.nome))}([^a-z0-9]|$)`, "g"),
      }));
    compiledCache.set(municipios, compiled);
  }
  return compiled;
}

export function findCity(normalizedText: string, municipios: IbgeMunicipio[]): IbgeMunicipio | undefined {
  for (const { municipio, regex } of compiledFor(municipios)) {
    regex.lastIndex = 0; // the same RegExp object is now reused across calls — reset its "g" state first.
    let match: RegExpExecArray | null;
    while ((match = regex.exec(normalizedText))) {
      const nameStart = match.index + match[1].length;
      if (!isPrecededByStreetPrefix(normalizedText, nameStart)) return municipio;
    }
  }
  return undefined;
}

// PA (Pará) deliberately omitted — see header.
const BR_STATE_NAMES: [string, string][] = [
  ["AC", "acre"], ["AL", "alagoas"], ["AP", "amapa"], ["AM", "amazonas"],
  ["BA", "bahia"], ["CE", "ceara"], ["DF", "distrito federal"],
  ["ES", "espirito santo"], ["GO", "goias"], ["MA", "maranhao"],
  ["MT", "mato grosso"], ["MS", "mato grosso do sul"], ["MG", "minas gerais"],
  ["PB", "paraiba"], ["PR", "parana"], ["PE", "pernambuco"], ["PI", "piaui"],
  ["RJ", "rio de janeiro"], ["RN", "rio grande do norte"],
  ["RS", "rio grande do sul"], ["RO", "rondonia"], ["RR", "roraima"],
  ["SC", "santa catarina"], ["SP", "sao paulo"], ["SE", "sergipe"],
  ["TO", "tocantins"],
];

// Only 26 fixed entries (unlike a state's own municipios list), so
// this is compiled once at module load rather than lazily cached.
const COMPILED_STATE_NAMES = [...BR_STATE_NAMES]
  .sort((a, b) => b[1].length - a[1].length)
  .map(([uf, name]) => ({ uf, regex: new RegExp(`(^|[^a-z0-9])${escapeRegExp(name)}([^a-z0-9]|$)`, "g") }));

export function findState(normalizedText: string): string | undefined {
  for (const { uf, regex } of COMPILED_STATE_NAMES) {
    regex.lastIndex = 0;
    let match: RegExpExecArray | null;
    while ((match = regex.exec(normalizedText))) {
      const nameStart = match.index + match[1].length;
      if (!isPrecededByStreetPrefix(normalizedText, nameStart)) return uf;
    }
  }
  return undefined;
}
