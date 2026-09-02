// BeeAware Global blueprint — DeCrimeAdapter (Germany Bundesland-level
// crime summary for the choropleth already used in Brazil/UK/Portugal/
// Spain/Northern Ireland/France).
//
// Investigated live (2026-09-08), not assumed:
// - BKA (Bundeskriminalamt, the federal criminal police office)
//   publishes the PKS (Polizeiliche Kriminalstatistik) since 2014 as
//   machine-readable files, not just PDF. The Land (state) level file
//   for 2025 (the newest complete year, published March 2026) is
//   XLSX-only — no CSV variant this year, unlike some earlier editions
//   — 1.7MB, 16 Bundesländer + one "Bundesrepublik Deutschland" national
//   total row (excluded below), with a much deeper category breakdown
//   than France's SSMSI (hundreds of Schlüssel codes vs 18).
// - Unlike data.gouv.fr (France), bka.de has no stable dataset API to
//   resolve the current file's URL — these are plain static
//   "Government Site Builder" pages. The URL below is hardcoded to the
//   2025 edition and WILL need a manual update once PKS2026 is
//   published (~March 2027) — same trade-off UnodcAdapter already
//   accepts for a source with no stable API, documented rather than
//   silently risked.
// - The real download needs `?__blob=publicationFile` appended — the
//   bare SharedDocs URL is an HTML landing page, not the file itself
//   (confirmed live: without it, the response is text/html, not a real
//   XLSX zip).
// - The workbook's one sheet is internally named with a garbled/
//   corrupted byte in place of "ä" (confirmed by reading the raw
//   xl/workbook.xml: literally `<sheet name="T01_L�" .../>`) — a bug in
//   BKA's own export tool, not something fixable by guessing the
//   intended name. Since the file has exactly one sheet,
//   `xl/worksheets/sheet1.xml` is read directly instead of using
//   xlsx_lite.ts's resolveSheetEntry() (which matches by exact name).
// - Numbers are real numeric XLSX cells here (unlike the Kreis-level
//   CSV variant, which uses a comma-as-thousands-separator text format)
//   — no string-number parsing quirk to handle.
// - Only leaf (non-aggregate) Schlüssel codes are used — this file's
//   Straftat breakdown is a hierarchy (e.g. "Diebstahl insgesamt" sums
//   several theft subtypes), and BKA's own Schlüssel scheme is uniform
//   nationally, confirmed against the separately-published Kreis-level
//   file's own distinct (Schlüssel, Straftat) pairs. Two categories are
//   deliberately excluded even though they're leaves: 725000 (residence/
//   asylum law violations — no physical-safety bucket, same reasoning
//   as France's excluded payment-fraud category) and 897000 Cybercrime
//   (same reasoning as Spain's excluded cybercrime fields). Financial
//   crimes (Betrug, Unterschlagung, Urkundenfälschung, Hehlerei) are
//   excluded for the same reason.
export const BUNDESLAND_NAMES: string[] = [
  "Baden-Württemberg",
  "Bayern",
  "Berlin",
  "Brandenburg",
  "Bremen",
  "Hamburg",
  "Hessen",
  "Mecklenburg-Vorpommern",
  "Niedersachsen",
  "Nordrhein-Westfalen",
  "Rheinland-Pfalz",
  "Saarland",
  "Sachsen",
  "Sachsen-Anhalt",
  "Schleswig-Holstein",
  "Thüringen",
];

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import { forEachRow, locateZipEntries, parseSharedStrings, inflateEntrySync } from "../../xlsx_lite.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const XLSX_URL =
  "https://www.bka.de/SharedDocs/Downloads/DE/Publikationen/PolizeilicheKriminalstatistik/2025/Land/Faelle/LA-F-02-T01-Laender-Faelle-HZ_xls.xlsx?__blob=publicationFile&v=2";
const REPORT_YEAR = "2025";
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";

// Schlüssel (crime code) -> [EventCategory, eventType, severity]. Only
// mutually-exclusive, non-double-counting leaves — see file header.
const CATEGORY_MAP: Record<string, [string, string, string]> = {
  "111000": ["VIOLENCE", "sexual_violence", "high"],
  "210000": ["PROPERTY", "robbery", "high"],
  "211000": ["PROPERTY", "robbery", "high"],
  "212000": ["PROPERTY", "robbery", "high"],
  "216000": ["PROPERTY", "robbery", "medium"],
  "217000": ["PROPERTY", "robbery", "medium"],
  "219000": ["PROPERTY", "robbery", "high"],
  "222000": ["VIOLENCE", "assault", "high"],
  "224000": ["VIOLENCE", "assault", "medium"],
  "326000": ["PROPERTY", "theft", "low"],
  "435000": ["PROPERTY", "burglary", "medium"],
  "436000": ["PROPERTY", "burglary", "medium"],
  "621110": ["PUBLIC_SAFETY", "disturbance", "medium"],
  "621120": ["VIOLENCE", "assault", "high"],
  "640000": ["PUBLIC_SAFETY", "fire", "high"],
  "674000": ["COMMUNITY", "other", "low"],
  "730000": ["PUBLIC_SAFETY", "drugs", "medium"],
  "892500": ["VIOLENCE", "homicide", "high"],
};

const BUNDESLAND_SET = new Set(BUNDESLAND_NAMES);

// German Land-level GeoPrecision tier — a Bundesland is Germany's own
// TOP administrative division (nothing above it, unlike a French
// département which sits below the région), so this uses 'STATE'
// (0.3), not the 'DISTRICT' (0.6) tier used for France/UK/Northern
// Ireland's intermediate-level areas.
const BUNDESLAND_LOCATION_CONFIDENCE = defaultLocationConfidence("STATE");

export class DeCrimeAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "DE",
      name: "BKA — Polizeiliche Kriminalstatistik (Länder-Falltabellen)",
      organisation: "Bundeskriminalamt (BKA)",
      sourceType: "official",
      sourceUrl: XLSX_URL,
      adapterName: "DeCrimeAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(XLSX_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) {
      throw new Error(`BKA PKS Länder XLSX request failed: ${res.status}`);
    }
    const bytes = new Uint8Array(await res.arrayBuffer());
    return [
      {
        sourceRecordId: "de-crime-land-feed",
        payload: bytes,
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const bytes = record.payload as Uint8Array;
    const entries = locateZipEntries(bytes);

    const sheetEntry = entries.get("xl/worksheets/sheet1.xml");
    const sharedStringsEntry = entries.get("xl/sharedStrings.xml");
    if (!sheetEntry || !sharedStringsEntry) return [];

    const sharedStrings = parseSharedStrings(await inflateEntrySync(bytes, sharedStringsEntry));

    // Columns confirmed live against the real file (positional, 0-based):
    // A=Schlüssel, B=Straftat, C=Bundesland, D=Anzahl erfasste Fälle.
    const COL = { schluessel: 0, straftat: 1, bundesland: 2, faelle: 3 };

    const events: SecurityEvent[] = [];
    await forEachRow(bytes, sheetEntry, sharedStrings, (cells) => {
      const bundesland = cells[COL.bundesland];
      // Filtering by a known Bundesland name (rather than skipping a
      // fixed number of header rows) also naturally excludes the
      // "Bundesrepublik Deutschland" national-total row.
      if (!bundesland || !BUNDESLAND_SET.has(bundesland)) return;

      const schluessel = cells[COL.schluessel];
      if (!schluessel) return;
      const mapped = CATEGORY_MAP[schluessel];
      if (!mapped) return;

      const count = Number(cells[COL.faelle]);
      if (!Number.isFinite(count) || count <= 0) return;

      const [eventCategory, eventType, severity] = mapped;
      events.push({
        countryCode: "DE",
        sourceRecordId: `de-crime-${bundesland}-${REPORT_YEAR}-${schluessel}`,
        sourceType: "official",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        occurredAt: `${REPORT_YEAR}-01-01T00:00:00Z`,
        geoPrecision: "STATE",
        locationConfidence: BUNDESLAND_LOCATION_CONFIDENCE,
        district: bundesland,
        occurrenceCount: count,
        severity,
        confidenceScore: computeConfidenceScore({
          reliabilityGrade: "official_confirmed_record",
          locationConfidence: BUNDESLAND_LOCATION_CONFIDENCE,
        }),
        rawPayload: { schluessel, bundesland, year: REPORT_YEAR },
      });
    });

    return events;
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(XLSX_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on XLSX` };
      }
      return { status: "GREEN", lastDataDate: new Date().toISOString().slice(0, 10) };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
