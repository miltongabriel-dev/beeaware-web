// BeeAware Global blueprint — German-language news classifier for
// de_news.ts, built in the same shape as fr_news_classifier.ts/
// es_news_classifier.ts (KEYWORD_MAP + EXCLUSION_KEYWORDS, first-match-
// wins). presseportal.de/blaulicht aggregates real police press
// releases nationwide, already curated to be about incidents, so
// EXCLUSION_KEYWORDS matters less here than on a general news portal.
//
// German compound words are generally long and distinctive, so — unlike
// fr_news_classifier.ts — this doesn't need word-boundary matching for
// most keywords. Two real exceptions, found deliberately by checking
// short/generic-looking stems against real German words before using
// them: bare "brand" (fire) is a literal substring of "Brandenburg" (a
// Bundesland name that will legitimately appear in unrelated
// datelines/text), and bare "schuss" (shot) is a literal substring of
// "Ausschuss" (committee). Both are avoided below in favour of longer,
// unambiguous compounds ("brandstiftung", "schüsse", "beschossen",
// "schusswaffe") that don't have this problem.
export function stripAccentsLower(s: string): string {
  return s.toLowerCase();
}

// keyword -> [eventCategory, eventType, severity]. Checked (in order)
// against the normalized (lowercase) title + description. Order
// matters: classifyDeNews() returns the FIRST match, so a more specific
// phrase must be listed before a broader word it contains (e.g.
// "mordversuch" before "mord").
const KEYWORD_MAP: [string, string, string, string][] = [
  ["mordversuch", "VIOLENCE", "attempted_homicide", "high"],
  ["versuchter mord", "VIOLENCE", "attempted_homicide", "high"],
  ["versuchter totschlag", "VIOLENCE", "attempted_homicide", "high"],
  ["mord", "VIOLENCE", "homicide", "high"],
  ["totschlag", "VIOLENCE", "homicide", "high"],
  ["tötungsdelikt", "VIOLENCE", "homicide", "high"],
  ["vergewaltigung", "VIOLENCE", "sexual_violence", "high"],
  ["sexuelle nötigung", "VIOLENCE", "sexual_violence", "high"],
  ["sexueller übergriff", "VIOLENCE", "sexual_violence", "high"],
  ["sexuelle belästigung", "VIOLENCE", "sexual_violence", "medium"],
  ["häusliche gewalt", "VIOLENCE", "domestic_violence", "medium"],
  ["gefährliche körperverletzung", "VIOLENCE", "assault", "high"],
  ["schwere körperverletzung", "VIOLENCE", "assault", "high"],
  ["körperverletzung", "VIOLENCE", "assault", "medium"],
  ["schlägerei", "VIOLENCE", "assault", "medium"],
  ["entführung", "VIOLENCE", "kidnapping", "high"],
  ["geiselnahme", "VIOLENCE", "kidnapping", "high"],
  ["raubüberfall", "PROPERTY", "robbery", "high"],
  ["handtaschenraub", "PROPERTY", "robbery", "medium"],
  ["überfall", "PROPERTY", "robbery", "high"],
  ["raub", "PROPERTY", "robbery", "high"],
  ["einbruch", "PROPERTY", "burglary", "medium"],
  ["einbrecher", "PROPERTY", "burglary", "medium"],
  ["ladendiebstahl", "PROPERTY", "theft", "low"],
  ["taschendiebstahl", "PROPERTY", "theft", "low"],
  ["diebstahl", "PROPERTY", "theft", "low"],
  ["entwendet", "PROPERTY", "theft", "low"],
  ["gestohlen", "PROPERTY", "theft", "low"],
  ["schüsse", "PUBLIC_SAFETY", "weapon", "high"],
  ["beschossen", "PUBLIC_SAFETY", "weapon", "high"],
  ["schusswaffe", "PUBLIC_SAFETY", "weapon", "high"],
  ["messerstich", "PUBLIC_SAFETY", "weapon", "high"],
  ["niedergestochen", "PUBLIC_SAFETY", "weapon", "high"],
  ["erstochen", "PUBLIC_SAFETY", "weapon", "high"],
  ["brandstiftung", "PUBLIC_SAFETY", "fire", "high"],
  ["rauschgift", "PUBLIC_SAFETY", "drugs", "medium"],
  ["betäubungsmittel", "PUBLIC_SAFETY", "drugs", "medium"],
  ["drogenhandel", "PUBLIC_SAFETY", "drugs", "medium"],
  ["bewusstlos", "PUBLIC_SAFETY", "emergency", "low"],
  ["vermisst", "PUBLIC_SAFETY", "emergency", "low"],
  ["widerstand gegen", "PUBLIC_SAFETY", "disturbance", "medium"],
  ["rangelei", "COMMUNITY", "disorder", "low"],
  ["graffiti", "COMMUNITY", "other", "low"],
  ["sachbeschädigung", "COMMUNITY", "other", "low"],
];

// Same reasoning as fr_news_classifier.ts's own EXCLUSION_KEYWORDS: if
// any of these also match, the article is a statistic/retrospective
// piece around a crime word, not a specific incident.
const EXCLUSION_KEYWORDS = [
  "bilanz", "statistik", "jahresbericht", "zunahme", "rückgang", "prozent", "%",
];

export function classifyDeNews(title: string, description: string): [string, string, string] | undefined {
  const normalized = stripAccentsLower(`${title} ${description}`);
  if (EXCLUSION_KEYWORDS.some((kw) => normalized.includes(kw))) return undefined;

  for (const [keyword, eventCategory, eventType, severity] of KEYWORD_MAP) {
    if (normalized.includes(keyword)) return [eventCategory, eventType, severity];
  }
  return undefined;
}
