// BeeAware Global blueprint — French-language news classifier for
// fr_news.ts, built in the same shape as adapters/global/
// es_news_classifier.ts (KEYWORD_MAP + EXCLUSION_KEYWORDS, first-match-
// wins). actu17.fr is a dedicated police/justice/faits-divers outlet
// (like La Vanguardia's "Sucesos" section for es_news.ts), so
// EXCLUSION_KEYWORDS matters less here than on a general national
// portal, but is kept for the same statistic/retrospective framing
// risk documented on that file.
//
// Departs from es_news_classifier.ts in one deliberate way: that file
// matches keywords with plain `.includes()` (substring), which is safe
// for the Spanish/Portuguese stems it uses but is NOT safe for French —
// confirmed live against actu17.fr's own real feed (2026-09-07): the
// short stems "vol" (theft) and "viol" (rape) are literal substrings of
// completely unrelated common words — "volontairement" contains "vol",
// "violent"/"violence"/"violemment" all contain "viol". A real item
// pulled live ("un violent incendie... provoqué volontairement") would
// have been misclassified as sexual violence AND theft under a plain
// substring check. `wordMatch()` below requires a real word boundary
// and excludes the specific colliding continuations.
export function stripAccentsLower(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

// Matches `stem` as a whole word (or the start of a longer inflected
// word, e.g. "vol" matching "voleur"/"volee"), but never when `stem` is
// immediately followed by one of `excludeContinuations` — e.g. "viol"
// followed by "ent"/"ence"/"emment" is "violent(e)"/"violence"/
// "violemment", not a form of "violer".
function wordMatch(text: string, stem: string, excludeContinuations: string[] = []): boolean {
  const exclusion = excludeContinuations.length > 0 ? `(?!${excludeContinuations.join("|")})` : "";
  const re = new RegExp(`(^|[^a-z])${stem}${exclusion}[a-z]*`, "i");
  return re.test(text);
}

// keyword -> [eventCategory, eventType, severity]. Checked (in order)
// against the normalized (lowercase, accent-stripped) title +
// description. Order matters: classifyFrNews() returns the FIRST match,
// so a more specific phrase must be listed before a broader word it
// contains (e.g. "tentative de meurtre" before "meurtre").
//
// Multi-word phrases below are matched with plain `.includes()` — long
// enough that a substring collision inside an unrelated word isn't a
// real risk (unlike the bare "vol"/"viol" stems, handled separately via
// wordMatch() in classifyFrNews()).
const KEYWORD_MAP: [string, string, string, string][] = [
  ["tentative de meurtre", "VIOLENCE", "attempted_homicide", "medium"],
  ["tentative d'assassinat", "VIOLENCE", "attempted_homicide", "medium"],
  ["tente de tuer", "VIOLENCE", "attempted_homicide", "medium"],
  ["assassinat", "VIOLENCE", "homicide", "high"],
  ["meurtre", "VIOLENCE", "homicide", "high"],
  ["homicide", "VIOLENCE", "homicide", "high"],
  ["feminicide", "VIOLENCE", "homicide", "high"],
  ["retrouve mort", "VIOLENCE", "homicide", "medium"],
  ["agression sexuelle", "VIOLENCE", "sexual_violence", "high"],
  ["abus sexuel", "VIOLENCE", "sexual_violence", "high"],
  ["violences conjugales", "VIOLENCE", "domestic_violence", "medium"],
  ["violence conjugale", "VIOLENCE", "domestic_violence", "medium"],
  ["violences intrafamiliales", "VIOLENCE", "domestic_violence", "medium"],
  ["enlevement", "VIOLENCE", "kidnapping", "high"],
  ["sequestration", "VIOLENCE", "kidnapping", "high"],
  ["agression homophobe", "VIOLENCE", "assault", "medium"],
  ["agression", "VIOLENCE", "assault", "medium"],
  ["coups de feu", "PUBLIC_SAFETY", "weapon", "high"],
  ["fusillade", "PUBLIC_SAFETY", "weapon", "high"],
  ["arme a feu", "PUBLIC_SAFETY", "weapon", "medium"],
  ["coups de couteau", "PUBLIC_SAFETY", "weapon", "high"],
  ["poignarde", "PUBLIC_SAFETY", "weapon", "high"],
  ["explosif", "PUBLIC_SAFETY", "weapon", "high"],
  ["cambriolage", "PROPERTY", "burglary", "medium"],
  ["braquage", "PROPERTY", "robbery", "high"],
  ["a main armee", "PROPERTY", "robbery", "high"],
  ["voleur", "PROPERTY", "theft", "low"],
  ["vol de vehicule", "PROPERTY", "vehicle_theft", "medium"],
  ["vol de voiture", "PROPERTY", "vehicle_theft", "medium"],
  ["victime de vol", "PROPERTY", "theft", "low"],
  ["trafic de stupefiants", "PUBLIC_SAFETY", "drugs", "medium"],
  ["trafic de drogue", "PUBLIC_SAFETY", "drugs", "medium"],
  ["incendie", "PUBLIC_SAFETY", "fire", "medium"],
];

// Same reasoning as es_news_classifier.ts's own EXCLUSION_KEYWORDS: if
// any of these also match, the article is a statistic/retrospective
// piece around a crime word, not a specific incident.
const EXCLUSION_KEYWORDS = [
  "bilan", "statistique", "sondage", "augmente", "augmentation de",
  "hausse de", "baisse de", "%", "candidat",
];

export function classifyFrNews(title: string, description: string): [string, string, string] | undefined {
  const normalized = stripAccentsLower(`${title} ${description}`);
  if (EXCLUSION_KEYWORDS.some((kw) => normalized.includes(kw))) return undefined;

  // Specific multi-word phrases first (e.g. "vol de vehicule" should
  // classify as vehicle_theft, not fall through to the generic "vol"
  // stem below) — same "specific before general" rule as
  // es_news_classifier.ts's own ordering comment.
  for (const [keyword, eventCategory, eventType, severity] of KEYWORD_MAP) {
    if (normalized.includes(keyword)) return [eventCategory, eventType, severity];
  }

  // Generic "viol"/"vol" stem fallback, word-boundary-guarded — see
  // file header. Checked last so a more specific phrase above always
  // wins first.
  if (wordMatch(normalized, "viol", ["ent", "ence", "emment"])) {
    return ["VIOLENCE", "sexual_violence", "high"];
  }
  if (wordMatch(normalized, "vol", ["ontair", "ontar", "ontier"])) {
    return ["PROPERTY", "theft", "low"];
  }

  return undefined;
}
