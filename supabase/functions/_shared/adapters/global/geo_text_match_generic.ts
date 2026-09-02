// BeeAware Global blueprint — free-text area-name matching, generalized
// from adapters/br/geo_text_match.ts's own findCity() for pt_news.ts and
// es_news.ts. That original is typed against Brazil's IbgeMunicipio
// (fetched live per-UF); PT/ES news matching instead works against a
// plain, already-known, fixed name list (CONCELHO_NAME/MUNICIPIO_NAME,
// exported from pt_crime.ts/es_crime.ts — the same 308/427 names their
// own geometry is keyed to, not a second copy). Same matching rules as
// the original: longest name first (so a specific match is tried before
// a shorter name it happens to contain), word-boundary anchored (not a
// bare .includes()), and guarded against a street-name false positive
// (e.g. "Rua Faro" naming a street after a place, not the place itself).

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function stripAccentsLower(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

// Portuguese, Spanish and French street-naming conventions all routinely
// borrow a place name for a street (Rua/Avenida in Portuguese, Calle/
// Avenida in Spanish, Rue/Avenue in French) — same false-positive shape
// geo_text_match.ts's own STREET_PREFIX_RE was built for, extended with
// the Spanish and then French prefixes.
const STREET_PREFIX_RE =
  /\b(?:av|avenida|avenue|r|rua|rue|al|alameda|allee|trav|travessa|rod|rodovia|rte|route|pca|praca|place|pl|estr|estrada|chemin|ch|impasse|quai|cours|calle|c|paseo|plaza|carretera|ctra|bd|boulevard)\.?\s*$/;

function isPrecededByStreetPrefix(text: string, matchIndex: number): boolean {
  return STREET_PREFIX_RE.test(text.slice(0, matchIndex));
}

// normalizedText must already be stripAccentsLower'd by the caller.
// candidateNames are matched normalized internally, but the ORIGINAL
// (accented) name is what's returned, since that's what geo_areas.name
// and district need to hold.
export function findAreaName(normalizedText: string, candidateNames: string[]): string | undefined {
  const sorted = [...candidateNames].sort((a, b) => b.length - a.length);
  for (const name of sorted) {
    const normalizedName = stripAccentsLower(name);
    if (!normalizedName) continue;
    const re = new RegExp(`(^|[^a-z0-9])${escapeRegExp(normalizedName)}([^a-z0-9]|$)`, "g");
    let match: RegExpExecArray | null;
    while ((match = re.exec(normalizedText))) {
      const nameStart = match.index + match[1].length;
      if (!isPrecededByStreetPrefix(normalizedText, nameStart)) return name;
    }
  }
  return undefined;
}
