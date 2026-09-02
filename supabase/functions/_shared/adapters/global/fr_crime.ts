// BeeAware Global blueprint — FrCrimeAdapter (France département-level
// crime summary for the choropleth already used in Brazil/UK/Portugal/
// Spain/Northern Ireland).
//
// Investigated live (2026-09-07), not assumed:
// - SSMSI (Service statistique ministériel de la sécurité intérieure,
//   part of the Ministère de l'Intérieur) publishes three annual crime
//   databases — commune, département, région — on data.gouv.fr, no key
//   needed. The département-level CSV is 101 rows x 18 indicators x 10
//   years (2016-2025, ~2MB), with NO statistical-secrecy suppression
//   (unlike the commune-level file, which masks small counts as "ndiff"
//   — this is exactly why département was chosen over commune for the
//   choropleth granularity). Latest edition confirmed live: "Édition
//   juillet 2026", closing out 2025 as the newest complete year.
// - The dataset's resource URLs are timestamped by publish date (e.g.
//   ".../20260709-120038/donnee-dep-....csv") and change on every new
//   edition — confirmed by comparing the July 2026 vs January 2026
//   editions' URLs in the same dataset. Hardcoding a snapshot URL would
//   silently 404 (or worse, silently keep serving 2025's snapshot
//   forever) after SSMSI's next annual publish. fetch() therefore always
//   resolves the current URL through the dataset's own stable API
//   endpoint first, the same way a browser landing on the dataset page
//   would, rather than hardcoding a resource URL.
// - DEPARTEMENT_NAME below maps each Code_departement to the exact name
//   used as geo_areas.name (20260907100000_fr_departement_geometry.sql)
//   — both built from the same source, france-geojson's
//   departements-avec-outre-mer.geojson (`code`/`nom` properties).
//   Confirmed live: all 101 codes match 1:1 between that geometry file
//   and the SSMSI CSV's own Code_departement values, zero orphans either
//   direction (metropolitan 01-95 incl. Corsica 2A/2B, plus overseas
//   971/972/973/974/976). Exported for fr_news.ts, which matches article
//   text against these same 101 names (via geo_text_match_generic.ts)
//   rather than keeping a second copy of the list.
// - Only 16 of the 18 published indicators are safe to sum without
//   double-counting — see CATEGORY_MAP below for the full mapping and
//   the two exclusions (the drug-usage parent total, and payment fraud).
export const DEPARTEMENT_NAME: Record<string, string> = {
  "01": "Ain",
  "02": "Aisne",
  "03": "Allier",
  "04": "Alpes-de-Haute-Provence",
  "05": "Hautes-Alpes",
  "06": "Alpes-Maritimes",
  "07": "Ardèche",
  "08": "Ardennes",
  "09": "Ariège",
  "10": "Aube",
  "11": "Aude",
  "12": "Aveyron",
  "13": "Bouches-du-Rhône",
  "14": "Calvados",
  "15": "Cantal",
  "16": "Charente",
  "17": "Charente-Maritime",
  "18": "Cher",
  "19": "Corrèze",
  "21": "Côte-d'Or",
  "22": "Côtes-d'Armor",
  "23": "Creuse",
  "24": "Dordogne",
  "25": "Doubs",
  "26": "Drôme",
  "27": "Eure",
  "28": "Eure-et-Loir",
  "29": "Finistère",
  "2A": "Corse-du-Sud",
  "2B": "Haute-Corse",
  "30": "Gard",
  "31": "Haute-Garonne",
  "32": "Gers",
  "33": "Gironde",
  "34": "Hérault",
  "35": "Ille-et-Vilaine",
  "36": "Indre",
  "37": "Indre-et-Loire",
  "38": "Isère",
  "39": "Jura",
  "40": "Landes",
  "41": "Loir-et-Cher",
  "42": "Loire",
  "43": "Haute-Loire",
  "44": "Loire-Atlantique",
  "45": "Loiret",
  "46": "Lot",
  "47": "Lot-et-Garonne",
  "48": "Lozère",
  "49": "Maine-et-Loire",
  "50": "Manche",
  "51": "Marne",
  "52": "Haute-Marne",
  "53": "Mayenne",
  "54": "Meurthe-et-Moselle",
  "55": "Meuse",
  "56": "Morbihan",
  "57": "Moselle",
  "58": "Nièvre",
  "59": "Nord",
  "60": "Oise",
  "61": "Orne",
  "62": "Pas-de-Calais",
  "63": "Puy-de-Dôme",
  "64": "Pyrénées-Atlantiques",
  "65": "Hautes-Pyrénées",
  "66": "Pyrénées-Orientales",
  "67": "Bas-Rhin",
  "68": "Haut-Rhin",
  "69": "Rhône",
  "70": "Haute-Saône",
  "71": "Saône-et-Loire",
  "72": "Sarthe",
  "73": "Savoie",
  "74": "Haute-Savoie",
  "75": "Paris",
  "76": "Seine-Maritime",
  "77": "Seine-et-Marne",
  "78": "Yvelines",
  "79": "Deux-Sèvres",
  "80": "Somme",
  "81": "Tarn",
  "82": "Tarn-et-Garonne",
  "83": "Var",
  "84": "Vaucluse",
  "85": "Vendée",
  "86": "Vienne",
  "87": "Haute-Vienne",
  "88": "Vosges",
  "89": "Yonne",
  "90": "Territoire de Belfort",
  "91": "Essonne",
  "92": "Hauts-de-Seine",
  "93": "Seine-Saint-Denis",
  "94": "Val-de-Marne",
  "95": "Val-d'Oise",
  "971": "Guadeloupe",
  "972": "Martinique",
  "973": "Guyane",
  "974": "La Réunion",
  "976": "Mayotte",
};

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

// Stable dataset-page API — never changes across SSMSI editions, unlike
// the timestamped resource URLs it points to.
const DATASET_API_URL =
  "https://www.data.gouv.fr/api/1/datasets/bases-statistiques-communale-departementale-et-regionale-de-la-delinquance-enregistree-par-la-police-et-la-gendarmerie-nationales/";
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";

// indicateur (French label, exact text as published) -> [EventCategory,
// eventType, severity]. Only mutually-exclusive, non-double-counting
// leaves of SSMSI's own 18-indicator breakdown are included.
//
// Excluded: "Usage de stupéfiants" (the parent total of the AFD/hors AFD
// split below — summing it alongside its own two children would double
// the count) and "Escroqueries et fraudes aux moyens de paiement"
// (payment fraud — a financial crime with no physical-safety bucket in
// this app's taxonomy, same reasoning already used to exclude
// cybercrime fields from EsCrimeAdapter).
const CATEGORY_MAP: Record<string, [string, string, string]> = {
  "Homicides": ["VIOLENCE", "homicide", "high"],
  "Tentatives d'homicide": ["VIOLENCE", "attempted_homicide", "high"],
  "Violences physiques intrafamiliales": ["VIOLENCE", "domestic_violence", "medium"],
  "Violences physiques hors cadre familial": ["VIOLENCE", "assault", "medium"],
  "Violences sexuelles": ["VIOLENCE", "sexual_violence", "high"],
  "Vols avec armes": ["PROPERTY", "robbery", "high"],
  "Vols violents sans arme": ["PROPERTY", "robbery", "medium"],
  "Vols sans violence contre des personnes": ["PROPERTY", "theft", "low"],
  "Cambriolages de logement": ["PROPERTY", "burglary", "medium"],
  "Vols de véhicule": ["PROPERTY", "vehicle_theft", "medium"],
  "Vols dans les véhicules": ["PROPERTY", "theft", "low"],
  "Vols d'accessoires sur véhicules": ["PROPERTY", "theft", "low"],
  "Destructions et dégradations volontaires": ["COMMUNITY", "other", "low"],
  "Usage de stupéfiants (AFD)": ["PUBLIC_SAFETY", "drugs", "low"],
  "Usage de stupéfiants (hors AFD)": ["PUBLIC_SAFETY", "drugs", "medium"],
  "Trafic de stupéfiants": ["PUBLIC_SAFETY", "drugs", "high"],
};

interface DatasetResource {
  title?: string;
  format?: string;
  url?: string;
}

// French département-level GeoPrecision tier — same as UkPoliceAdapter's
// Police Force Area and NiPoliceAdapter's LGD (~100 areas nationwide,
// finer than a région/state but coarser than a commune/municipality).
const DEPARTMENT_LOCATION_CONFIDENCE = defaultLocationConfidence("DISTRICT");

function parseCsvLine(line: string): string[] {
  return line.split(";").map((f) => f.replace(/^"|"$/g, ""));
}

export class FrCrimeAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "FR",
      name: "data.gouv.fr — Bases statistiques départementale de la délinquance (SSMSI)",
      organisation: "SSMSI — Service statistique ministériel de la sécurité intérieure (Ministère de l'Intérieur)",
      sourceType: "official",
      sourceUrl: DATASET_API_URL,
      adapterName: "FrCrimeAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly",
    };
  }

  private async resolveCsvUrl(): Promise<string> {
    const res = await fetch(DATASET_API_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) {
      throw new Error(`data.gouv.fr dataset API request failed: ${res.status}`);
    }
    const json = await res.json();
    const resources = (json.resources ?? []) as DatasetResource[];
    const depResource = resources.find(
      (r) => r.format === "csv" && (r.title ?? "").toLowerCase().includes("départementale"),
    );
    if (!depResource?.url) {
      throw new Error("Could not find département-level CSV resource in data.gouv.fr dataset API response");
    }
    return depResource.url;
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const csvUrl = await this.resolveCsvUrl();
    const res = await fetch(csvUrl, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) {
      throw new Error(`SSMSI département CSV request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "fr-crime-dep-feed",
        payload: await res.text(),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const csv = record.payload as string;
    const lines = csv.split("\n").filter((l) => l.trim().length > 0);
    if (lines.length < 2) return [];

    // Columns (by position, confirmed live 2026-09-07):
    // Code_departement;Code_region;annee;indicateur;unite_de_compte;
    // nombre;taux_pour_mille;insee_pop;insee_pop_millesime;insee_log;
    // insee_log_millesime
    type Row = { deptCode: string; year: string; indicateur: string; nombre: string };
    const rows: Row[] = [];
    let maxYear = "";
    for (let i = 1; i < lines.length; i++) {
      const f = parseCsvLine(lines[i]);
      if (f.length < 6) continue;
      const deptCode = f[0];
      const year = f[2];
      const indicateur = f[3];
      const nombre = f[5];
      rows.push({ deptCode, year, indicateur, nombre });
      if (year > maxYear) maxYear = year;
    }

    const events: SecurityEvent[] = [];
    for (const row of rows) {
      if (row.year !== maxYear) continue; // only the latest complete year — see header
      const mapped = CATEGORY_MAP[row.indicateur];
      if (!mapped) continue;
      const count = Number(row.nombre);
      if (!Number.isFinite(count) || count <= 0) continue;
      const departementName = DEPARTEMENT_NAME[row.deptCode];
      if (!departementName) continue;

      const [eventCategory, eventType, severity] = mapped;
      events.push({
        countryCode: "FR",
        sourceRecordId: `fr-crime-dep-${row.deptCode}-${row.year}-${row.indicateur}`,
        sourceType: "official",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        occurredAt: `${row.year}-01-01T00:00:00Z`,
        geoPrecision: "DISTRICT",
        locationConfidence: DEPARTMENT_LOCATION_CONFIDENCE,
        district: departementName,
        occurrenceCount: count,
        severity,
        confidenceScore: computeConfidenceScore({
          reliabilityGrade: "official_confirmed_record",
          locationConfidence: DEPARTMENT_LOCATION_CONFIDENCE,
        }),
        rawPayload: { indicateur: row.indicateur, deptCode: row.deptCode, year: row.year },
      });
    }
    return events;
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const csvUrl = await this.resolveCsvUrl();
      const res = await fetch(csvUrl, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on CSV` };
      }
      return { status: "GREEN", lastDataDate: new Date().toISOString().slice(0, 10) };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
