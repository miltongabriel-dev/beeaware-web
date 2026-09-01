// BeeAware Global blueprint — Spanish-language news classifier for
// es_news.ts, built in the exact same shape as adapters/br/
// pt_news_classifier.ts (KEYWORD_MAP + EXCLUSION_KEYWORDS + DEATH_WORDS,
// first-match-wins, same two known/accepted failure modes documented on
// that file: a headline built entirely around a name with no listed
// keyword is silently skipped, and a differently-worded statistics piece
// could still slip past EXCLUSION_KEYWORDS). Unlike the PT-BR classifier
// (built for general national portals), this feeds off La Vanguardia's
// dedicated "Sucesos" section (already curated to be about incidents),
// so EXCLUSION_KEYWORDS matters less here but is kept for the same
// retrospective/statistic framing risk.

export function stripAccentsLower(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

// keyword -> [eventCategory, eventType, severity]. Checked as substring
// matches against the normalized (lowercase, accent-stripped) title +
// description. Order matters: classifyEsNews() returns the FIRST match,
// so a more specific phrase must be listed before a broader word it
// contains (e.g. "intento de asesinato" before "asesinato").
const KEYWORD_MAP: [string, string, string, string][] = [
  ["intento de asesinato", "VIOLENCE", "attempted_homicide", "medium"],
  ["intento de homicidio", "VIOLENCE", "attempted_homicide", "medium"],
  ["intentar matar", "VIOLENCE", "attempted_homicide", "medium"],
  ["asesinat", "VIOLENCE", "homicide", "high"],
  ["homicidio", "VIOLENCE", "homicide", "high"],
  ["muere apunalad", "VIOLENCE", "homicide", "high"],
  ["muere tiroteado", "VIOLENCE", "homicide", "high"],
  ["muere tiroteada", "VIOLENCE", "homicide", "high"],
  ["feminicidio", "VIOLENCE", "femicide", "high"],
  ["violacion", "VIOLENCE", "sexual_violence", "high"],
  ["agresion sexual", "VIOLENCE", "sexual_violence", "high"],
  ["abuso sexual", "VIOLENCE", "sexual_violence", "high"],
  ["violencia de genero", "VIOLENCE", "domestic_violence", "medium"],
  ["violencia domestica", "VIOLENCE", "domestic_violence", "medium"],
  ["maltrat", "VIOLENCE", "domestic_violence", "medium"],
  ["secuestr", "VIOLENCE", "kidnapping", "high"],
  ["atraco", "PROPERTY", "robbery", "medium"],
  ["atracador", "PROPERTY", "robbery", "medium"],
  ["robo", "PROPERTY", "robbery", "medium"],
  ["robad", "PROPERTY", "robbery", "medium"],
  ["hurto", "PROPERTY", "theft", "low"],
  ["hurtad", "PROPERTY", "theft", "low"],
  ["tiroteo", "PUBLIC_SAFETY", "weapon", "high"],
  ["disparo", "PUBLIC_SAFETY", "weapon", "high"],
  ["apunalad", "PUBLIC_SAFETY", "weapon", "high"],
  ["apunala", "PUBLIC_SAFETY", "weapon", "high"],
  ["narcotrafic", "PUBLIC_SAFETY", "drugs", "medium"],
  ["trafico de drogas", "PUBLIC_SAFETY", "drugs", "medium"],
  ["incendio", "PUBLIC_SAFETY", "fire", "medium"],
  ["vuelco", "ROAD_SAFETY", "accident", "medium"],
  ["colision", "ROAD_SAFETY", "accident", "medium"],
  ["atropell", "ROAD_SAFETY", "accident", "medium"],
  ["accidente", "ROAD_SAFETY", "accident", "low"],
];

// Same reasoning as pt_news_classifier.ts's own EXCLUSION_KEYWORDS: if
// any of these also match, the article is a statistic/retrospective
// piece around a crime word, not a specific incident.
const EXCLUSION_KEYWORDS = [
  "balance", "estadistica", "encuesta", "sondeo", "aumenta", "aumento de",
  "sube ", "subio ", "cae ", "cayo ", "descenso de", "%", "candidato",
];

// Only used to upgrade an already-matched ROAD_SAFETY "accidente" to
// fatal_accident — never a standalone trigger (same reasoning as
// pt_news_classifier.ts's DEATH_WORDS: "found dead"/"murio" describes any
// death discovery, not specifically a homicide).
const DEATH_WORDS = ["murio", "muerto", "muerta", "fallecid", "fallece"];

export function classifyEsNews(title: string, description: string): [string, string, string] | undefined {
  const normalized = stripAccentsLower(`${title} ${description}`);
  if (EXCLUSION_KEYWORDS.some((kw) => normalized.includes(kw))) return undefined;

  for (const [keyword, eventCategory, eventType, severity] of KEYWORD_MAP) {
    if (!normalized.includes(keyword)) continue;
    if (eventType === "accident" && DEATH_WORDS.some((w) => normalized.includes(w))) {
      return [eventCategory, "fatal_accident", "high"];
    }
    return [eventCategory, eventType, severity];
  }
  return undefined;
}
