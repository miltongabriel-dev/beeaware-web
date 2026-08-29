// BeeAware — shared Portuguese-language news classifier.
//
// Originally g1_news.ts's own KEYWORD_MAP/EXCLUSION_KEYWORDS/DEATH_WORDS/
// classify() (roadmap 5.2's "is_event / content_type" distinction) —
// extracted here once a second Portuguese-language news source needed
// the exact same allowlist. Every adapter importing this
// (g1_news.ts, cnn_brasil_news.ts, metropoles_news.ts, uol_news.ts,
// agencia_brasil_news.ts, diario_online_news.ts, folha_news.ts) shares
// the same two known, accepted failure modes documented on the original
// g1_news.ts commit:
//   - False negative: a genuine incident whose headline doesn't use any
//     listed keyword (e.g. built entirely around a victim's name) is
//     silently skipped.
//   - False positive: EXCLUSION_KEYWORDS filters out the clearest
//     statistical/retrospective framing ("Roubo cai 18% no Pará em
//     2026" — matches "roubo" but also "cai", so it's dropped), but a
//     differently-worded statistics piece could still slip through.
// Both are accuracy trade-offs to revisit if/when this project adds real
// article classification, not bugs in this implementation.

export function stripAccentsLower(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

// keyword -> [eventCategory, eventType, severity]. Checked as substring
// matches against the normalized (lowercase, accent-stripped) title +
// subtitle. Order matters: classifyPtBrNews() returns the FIRST match,
// so a more specific phrase (e.g. "tentativa de latrocínio") must be
// listed before the broader word it contains ("latrocínio") or it would
// never be reached.
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
// word, not reporting a specific incident — skip regardless of which
// KEYWORD_MAP entry matched. Found live (g1_news.ts): a candidate's
// stump speech mentioning "roubos de celulares" while criticising public
// safety policy matched "roubo" with nothing else to tell it apart from
// a real robbery report — "candidato" is a cheap, real signal that this
// is commentary, not an occurrence.
const EXCLUSION_KEYWORDS = [
  "balanco", "estatistica", "levantamento", "pesquisa", "aponta",
  "cai ", "caiu ", "subiu ", "sobe ", "aumenta", "aumento de", "recuo",
  "queda de", "ranking", "comparad", "%", "candidato",
];

// Words indicating a death, checked only to upgrade an already-matched
// road-safety accident to fatal_accident/high — NOT used as a classifier
// trigger on their own. Found live: "encontrado morto"/"encontrada morta"
// were tried as direct VIOLENCE/homicide triggers and immediately
// produced real false positives (a drowning while on holiday, a body
// found after a missing-persons search of unstated cause) — "found
// dead" describes any death discovery, not specifically a homicide.
const DEATH_WORDS = ["morreu", "morto", "morta", "morte", "obito"];

// "homicídio CULPOSO" is Brazilian legal language for a death caused by
// negligence (traffic, workplace) — not the doloso (intentional) crime
// this project's "homicide" category means everywhere else. Found live:
// a worker fatally struck by a garbage truck was reported as
// "registrado como homicídio culposo" — matching plain "homicidio"/
// "latrocinio" would have mislabeled a workplace accident as an
// intentional violent crime.
function isCulposo(normalized: string): boolean {
  return normalized.includes("culposo");
}

const HOMICIDE_FAMILY_TYPES = new Set(["homicide", "attempted_homicide", "femicide"]);

export function classifyPtBrNews(title: string, subtitle: string): [string, string, string] | undefined {
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
