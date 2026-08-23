// BeeAware Global blueprint — UnodcAdapter (Phase 1: global baseline).
//
// The first adapter in this codebase that isn't Brazil-specific — lives
// under adapters/global/, not adapters/br/, and produces its own
// countryCode per row instead of a file-wide constant. Source:
// data.unodc.org's "intentional homicide" Crime Trends Survey export,
// linked from https://data.unodc.org/datareport/hom-victim — verified
// live on 2026-08-23: downloaded and parsed the real
// data_cts_intentional_homicide.xlsx, 126083 rows, 204 country/territory
// entries, years through 2024. Brazil's yearly counts (2017: 63788 →
// 2024: 39625) match known real trends — this is real published UN
// statistics, not a scrape of something informal.
//
// A second UNODC file — data_cts_violent_and_sexual_crime.xlsx, which
// would have given a PROPERTY/broader-VIOLENCE baseline alongside
// homicide — was investigated and found to be genuinely corrupted on
// UNODC's own server: correct Content-Type/Content-Length/ETag headers,
// but the response bytes don't start with the ZIP signature every XLSX
// file must have, reproduced identically across three independent
// re-fetches (plain UA, with the site's session cookie, with
// --compressed). A real bug on their end, not fixable from here —
// deferred, not retried. Homicide-only for now.
//
// Two real data quirks in the ISO3 codes UNODC publishes, both handled
// rather than glossed over:
//   - The UK reports as three separate rows (GBR_E_W, GBR_S, GBR_NI —
//     England & Wales, Scotland and Northern Ireland don't share a
//     criminal-justice system) with NO plain "GBR" rollup ever published.
//   - Iraq published a plain "IRQ" national rollup only through 2013;
//     from 2014 on, only "IRQ_C" (Central Iraq) is reported, and
//     "IRQ_KRI" (Kurdistan Region) stops appearing after 2013 too — a
//     real gap in what Iraq itself reports, not something to paper over.
// MERGE_GROUPS below resolves both onto the single GB/IQ row this
// schema's country_code expects, by summing whatever variants share the
// most recent year available (see resolveCountries() for why this is
// safe for a latest-year-only snapshot but would need more care if this
// adapter ever ingests full history).
//
// Only the latest available year per country is ingested — a rolling
// baseline snapshot for the "no local data" fallback case, not a trend
// line. The two merged countries (GB, IQ) default to severity "medium"
// since a summed count has no single matching rate row to tier —
// documented here as a known limitation for 2 of ~199 countries, not a
// silent guess.
//
// Uses xlsx_lite.ts, not the `xlsx` (SheetJS) package pa_segup.ts uses —
// found the hard way, not by preference. This file's real sheet is
// 126083 rows / 61.5MB of XML; SheetJS's full per-cell object model of
// it measured 300-550MB regardless of its own large-file tuning options,
// and the deployed function failed with WORKER_RESOURCE_LIMIT. See
// xlsx_lite.ts's header for the streaming approach that replaced it —
// same class of fix as rs_ssp.ts's native-decompression rewrite, applied
// to XLSX instead of CSV-in-zip.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import { forEachRow, locateZipEntries, parseSharedStrings, inflateEntrySync, resolveSheetEntry } from "../../xlsx_lite.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const PAGE_URL = "https://data.unodc.org/datareport/hom-victim";
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";

const LINK_PATTERN =
  /href="(\/sites\/dataportal\.unodc\.org\/files\/(\d{4}-\d{2})\/data_cts_intentional_homicide\.xlsx)"/;

interface UnodcFile {
  period: string;
  url: string;
}

function findCurrentFile(html: string): UnodcFile | undefined {
  const match = html.match(LINK_PATTERN);
  if (!match) return undefined;
  return { period: match[2], url: `https://data.unodc.org${match[1]}` };
}

// ISO 3166-1 alpha-3 -> alpha-2, restricted to exactly the 197 codes
// UNODC's homicide file uses that map onto a standard country (verified
// live against the real file's country list via the `i18n-iso-countries`
// reference package, not hand-typed) — stable public reference data, not
// something this adapter derives or guesses. Two codes UNODC publishes
// have no standard mapping at all (CHA "Channel Island" — Jersey/
// Guernsey don't share one ISO2 code; XKX "Kosovo" — not a
// standardised ISO 3166-1 assignment) and are deliberately absent here,
// so normalize() skips them rather than inventing a code.
const ISO3_TO_ISO2: Record<string, string> = {
  ABW: "AW", AFG: "AF", AGO: "AO", AIA: "AI", ALB: "AL", AND: "AD", ARE: "AE", ARG: "AR",
  ARM: "AM", ASM: "AS", ATG: "AG", AUS: "AU", AUT: "AT", AZE: "AZ", BDI: "BI", BEL: "BE",
  BGD: "BD", BGR: "BG", BHR: "BH", BHS: "BS", BIH: "BA", BLR: "BY", BLZ: "BZ", BMU: "BM",
  BOL: "BO", BRA: "BR", BRB: "BB", BRN: "BN", BTN: "BT", BWA: "BW", CAN: "CA", CHE: "CH",
  CHL: "CL", CHN: "CN", CMR: "CM", COK: "CK", COL: "CO", CPV: "CV", CRI: "CR", CUB: "CU",
  CUW: "CW", CYM: "KY", CYP: "CY", CZE: "CZ", DEU: "DE", DMA: "DM", DNK: "DK", DOM: "DO",
  DZA: "DZ", ECU: "EC", EGY: "EG", ERI: "ER", ESP: "ES", EST: "EE", ETH: "ET", FIN: "FI",
  FJI: "FJ", FRA: "FR", FSM: "FM", GEO: "GE", GHA: "GH", GIB: "GI", GLP: "GP", GNB: "GW",
  GRC: "GR", GRD: "GD", GRL: "GL", GTM: "GT", GUF: "GF", GUM: "GU", GUY: "GY", HKG: "HK",
  HND: "HN", HRV: "HR", HTI: "HT", HUN: "HU", IDN: "ID", IMN: "IM", IND: "IN", IRL: "IE",
  IRN: "IR", IRQ: "IQ", ISL: "IS", ISR: "IL", ITA: "IT", JAM: "JM", JOR: "JO", JPN: "JP",
  KAZ: "KZ", KEN: "KE", KHM: "KH", KIR: "KI", KNA: "KN", KOR: "KR", KWT: "KW", LBN: "LB",
  LBR: "LR", LCA: "LC", LIE: "LI", LKA: "LK", LSO: "LS", LTU: "LT", LUX: "LU", LVA: "LV",
  MAC: "MO", MAF: "MF", MAR: "MA", MCO: "MC", MDA: "MD", MDV: "MV", MEX: "MX", MKD: "MK",
  MLT: "MT", MMR: "MM", MNE: "ME", MNG: "MN", MOZ: "MZ", MRT: "MR", MSR: "MS", MTQ: "MQ",
  MUS: "MU", MWI: "MW", MYS: "MY", MYT: "YT", NAM: "NA", NCL: "NC", NER: "NE", NGA: "NG",
  NIC: "NI", NLD: "NL", NOR: "NO", NPL: "NP", NZL: "NZ", OMN: "OM", PAK: "PK", PAN: "PA",
  PER: "PE", PHL: "PH", PLW: "PW", PNG: "PG", POL: "PL", PRI: "PR", PRT: "PT", PRY: "PY",
  PSE: "PS", PYF: "PF", QAT: "QA", REU: "RE", ROU: "RO", RUS: "RU", RWA: "RW", SAU: "SA",
  SGP: "SG", SHN: "SH", SLB: "SB", SLE: "SL", SLV: "SV", SMR: "SM", SPM: "PM", SRB: "RS",
  SSD: "SS", STP: "ST", SUR: "SR", SVK: "SK", SVN: "SI", SWE: "SE", SWZ: "SZ", SYC: "SC",
  SYR: "SY", TCA: "TC", THA: "TH", TJK: "TJ", TKM: "TM", TLS: "TL", TON: "TO", TTO: "TT",
  TUN: "TN", TUR: "TR", TUV: "TV", TZA: "TZ", UGA: "UG", UKR: "UA", URY: "UY", USA: "US",
  UZB: "UZ", VAT: "VA", VCT: "VC", VEN: "VE", VGB: "VG", VIR: "VI", VNM: "VN", VUT: "VU",
  WSM: "WS", YEM: "YE", ZAF: "ZA", ZMB: "ZM", ZWE: "ZW",
};

// See file header — these ISO3 variants all resolve to one merged ISO2
// country rather than the plain ISO3_TO_ISO2 table.
const MERGE_GROUPS: Record<string, string> = {
  GBR_E_W: "GB", GBR_S: "GB", GBR_NI: "GB",
  IRQ: "IQ", IRQ_C: "IQ", IRQ_KRI: "IQ",
};
const MERGED_COUNTRY_CODES = new Set(Object.values(MERGE_GROUPS));

interface UnodcRow {
  Iso3_code: string;
  Country: string;
  Indicator: string;
  Dimension: string;
  Category: string;
  Sex: string;
  Age: string;
  Year: number;
  "Unit of measurement": string;
  VALUE: number;
}

interface ResolvedCountry {
  countryCode: string;
  countryName: string;
  year: number;
  count: number;
  rate: number | undefined; // undefined for merged countries — see file header
}

// Groups every ISO3 variant that resolves to the same country, takes
// whichever year is most recent across that group's rows, and sums the
// count for that single year. Safe for a latest-year-only snapshot
// because the max-year row set never includes overlapping variants that
// would double-count (verified against the real file: Iraq's plain
// "IRQ" rollup and its IRQ_C/IRQ_KRI parts never both have data for the
// current latest year — IRQ stops in 2013, IRQ_C continues past it).
// Ingesting full history would need to prefer the plain code over its
// parts explicitly instead of relying on that — noted for when this
// adapter grows beyond a single snapshot.
function resolveCountries(rows: UnodcRow[]): ResolvedCountry[] {
  const byCountryCode = new Map<string, UnodcRow[]>();

  for (const row of rows) {
    const countryCode = MERGE_GROUPS[row.Iso3_code] ?? ISO3_TO_ISO2[row.Iso3_code];
    if (!countryCode) continue; // no standard mapping — skip rather than guess
    const list = byCountryCode.get(countryCode) ?? [];
    list.push(row);
    byCountryCode.set(countryCode, list);
  }

  const resolved: ResolvedCountry[] = [];

  for (const [countryCode, countryRows] of byCountryCode) {
    const countRows = countryRows.filter((r) => r["Unit of measurement"] === "Counts");
    if (countRows.length === 0) continue;

    const maxYear = Math.max(...countRows.map((r) => r.Year));
    const latestCountRows = countRows.filter((r) => r.Year === maxYear);
    // Almost always a whole tally, but UNODC's own "Counts" unit carries
    // modeled/estimated point values (not raw reports) for a handful of
    // small territories with incomplete direct reporting — e.g. French
    // Guiana 2020: 38.69901, Cook Islands 2012: 0.6280951 (verified in the
    // real file, 2 of 198 countries). occurrence_count is an integer
    // column; round rather than truncate so a sub-1 estimate like Cook
    // Islands' doesn't silently disappear as 0.
    const count = Math.round(latestCountRows.reduce((sum, r) => sum + r.VALUE, 0));

    const isMerged = MERGED_COUNTRY_CODES.has(countryCode);
    let rate: number | undefined;
    if (!isMerged) {
      const rateRow = countryRows.find(
        (r) => r.Year === maxYear && r["Unit of measurement"] === "Rate per 100,000 population",
      );
      rate = rateRow?.VALUE;
    }

    resolved.push({
      countryCode,
      countryName: latestCountRows[0].Country,
      year: maxYear,
      count,
      rate,
    });
  }

  return resolved;
}

function severityFromRate(rate: number | undefined): string {
  if (rate == null) return "medium"; // merged countries — see file header
  if (rate > 10) return "high";
  if (rate >= 3) return "medium";
  return "low";
}

export class UnodcAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "XX", // global source, not scoped to one country
      name: "UNODC - Intentional Homicide (Crime Trends Survey)",
      organisation: "United Nations Office on Drugs and Crime",
      sourceType: "official",
      sourceUrl: PAGE_URL,
      adapterName: "UnodcAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly", // this data changes at most yearly; monthly just keeps health current
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const pageRes = await fetch(PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!pageRes.ok) {
      throw new Error(`UNODC page request failed: ${pageRes.status}`);
    }
    const html = await pageRes.text();
    const file = findCurrentFile(html);
    if (!file) {
      return [];
    }

    const fileRes = await fetch(file.url, { headers: { "User-Agent": USER_AGENT } });
    if (!fileRes.ok) {
      throw new Error(`UNODC file download failed: ${fileRes.status}`);
    }

    return [
      {
        sourceRecordId: file.url,
        payload: new Uint8Array(await fileRes.arrayBuffer()),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const bytes = record.payload as Uint8Array;
    const entries = locateZipEntries(bytes);

    const sheetEntry = await resolveSheetEntry(bytes, entries, "data_cts_intentional_homicide");
    const sharedStringsEntry = entries.get("xl/sharedStrings.xml");
    if (!sheetEntry || !sharedStringsEntry) return [];

    const sharedStrings = parseSharedStrings(await inflateEntrySync(bytes, sharedStringsEntry));

    // Fixed column layout confirmed against the real file's header row
    // (Excel row 3 — row 1 is a title/contact line, row 2 a lone date
    // stamp): Iso3_code, Country, Region, Subregion, Indicator,
    // Dimension, Category, Sex, Age, Year, Unit of measurement, VALUE,
    // Source. Read by position rather than re-deriving the header from
    // the streamed rows, since xlsx_lite streams row-by-row and doesn't
    // build a header/lookup structure — a defensive check below bails
    // out if a future export's header doesn't match, rather than
    // silently misreading columns.
    const COL = {
      iso3: 0, country: 1, indicator: 4, dimension: 5,
      category: 6, sex: 7, age: 8, year: 9, unit: 10, value: 11,
    };

    const filtered: UnodcRow[] = [];
    let headerRowIndex = 0;
    let headerVerified = false;

    await forEachRow(bytes, sheetEntry, sharedStrings, (cells) => {
      headerRowIndex++;
      if (headerRowIndex === 3) {
        headerVerified = cells[COL.iso3] === "Iso3_code" && cells[COL.indicator] === "Indicator";
        return;
      }
      if (headerRowIndex <= 3 || !headerVerified) return;

      if (
        cells[COL.indicator] !== "Victims of intentional homicide" ||
        cells[COL.dimension] !== "Total" ||
        cells[COL.category] !== "Total" ||
        cells[COL.sex] !== "Total" ||
        cells[COL.age] !== "Total"
      ) return;
      const unit = cells[COL.unit];
      if (unit !== "Counts" && unit !== "Rate per 100,000 population") return;

      filtered.push({
        Iso3_code: cells[COL.iso3] ?? "",
        Country: cells[COL.country] ?? "",
        Indicator: cells[COL.indicator] ?? "",
        Dimension: cells[COL.dimension] ?? "",
        Category: cells[COL.category] ?? "",
        Sex: cells[COL.sex] ?? "",
        Age: cells[COL.age] ?? "",
        Year: Number(cells[COL.year]),
        "Unit of measurement": unit,
        VALUE: Number(cells[COL.value]),
      });
    });

    if (!headerVerified) {
      throw new Error("UNODC sheet header didn't match the expected column layout — source format may have changed");
    }

    const countryLocationConfidence = defaultLocationConfidence("COUNTRY");

    const events: SecurityEvent[] = resolveCountries(filtered).map((c) => {
      const severity = severityFromRate(c.rate);
      return {
        countryCode: c.countryCode,
        sourceRecordId: `${c.countryCode}-${c.year}-homicide`,
        sourceType: "official",
        eventCategory: "VIOLENCE",
        eventType: "homicide",
        originalCategory: "Victims of intentional homicide",
        occurredAt: `${c.year}-01-01T00:00:00Z`,
        geoPrecision: "COUNTRY",
        locationConfidence: countryLocationConfidence,
        occurrenceCount: c.count,
        severity,
        confidenceScore: computeConfidenceScore({
          reliabilityGrade: "official_confirmed_record",
          locationConfidence: countryLocationConfidence,
        }),
      };
    });

    return events;
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on source page` };
      }
      const html = await res.text();
      const file = findCurrentFile(html);
      if (!file) {
        return { status: "RED", message: "No dataset download link found — page markup may have changed" };
      }
      return { status: "GREEN", lastDataDate: `${file.period}-01` };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
