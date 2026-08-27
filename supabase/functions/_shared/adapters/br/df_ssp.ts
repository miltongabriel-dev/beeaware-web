// BeeAware Brasil roadmap / Phase 8 — DfAdapter (Distrito Federal, SSP-DF
// "Balanço Criminal" official statistics). One of the two states left over
// from the roadmap's own "second-wave" list (11.9: Minas Gerais, Ceará,
// Bahia, Rio Grande do Sul, Espírito Santo, Distrito Federal) — MG/BA/RS/ES
// already have adapters; Ceará's SSPDS site sits behind a WAF (volt-adc)
// that 403s even a browser-UA request server-side, the same "not fixable
// from here" shape as SSP-BA's broken TLS chain (ba_ssp.ts's own header).
// DF has no such blocker.
//
// Real source, verified live 2026-08-27:
// https://www.ssp.df.gov.br/dados-por-regiao-administrativa/ lists a PDF+XLS
// pair for every year since 2014, for the state as a whole AND separately
// for each of DF's ~35 administrative regions (RAs). Only the state-wide
// "DISTRITO FEDERAL" pair is used here — summing 35 per-RA files would give
// the same totals with far more requests and no benefit yet (RA-level
// geography isn't wired into geo_areas for DF the way RJ's CISP/AISP/RISP
// are; that's a real follow-up, not implemented here).
//
// The listing page's exact download URLs are NOT year-patterned like MG's
// (crimes_violentos_{year}.csv) — Liferay document IDs are opaque revision
// numbers (00_distrito-federal-3-xlsx, distrito-federal-4-xlsx,
// distrito-federal_1-xlsx, ...), so the year has to be read off the page's
// own "🗓️ YYYY" label next to each link, not guessed from the filename.
// findStatewideYearFiles() below does that: matches every state-wide xlsx
// href (filtered by filename — distrito-federal/balanco-criminal/df-YYYY,
// none of which ever appear in a per-RA slug like "20_aguas-claras-3-xlsx"),
// then looks backward for the nearest "(\d{4})...</strong>" year label.
// Verified against the real live page for all 9 years it lists (2018-2026):
// 100% correct extraction, including the two label shapes actually used
// (some years wrap just the digits in <strong>, 2026's own entry wraps a
// whole "🏙️ DISTRITO FEDERAL 🗓️ 2026" span instead).
//
// Scoped to the 2 most recent years (YEARS_WINDOW) — same rationale as
// MgAdapter: each file is tiny here (33-41KB, nothing like MG's multi-MB
// concern), but older years (2018-2021) are old CMS uploads not verified
// to share this exact layout, and DF's own "atualizado em" note shows the
// current year's file is a rolling monthly update, so 2 years covers
// "current + last complete year" without betting on undocumented history.
//
// Format: NOT a data table — a printed report matrix (NATUREZA rows ×
// month columns), same shape class as RJ-ISP's polygon summaries, just
// wider. Confirmed by downloading and inspecting the real 2025 and 2026
// files byte-for-byte (unzip + inspect xl/worksheets/sheet1.xml directly,
// not a library): one sheet named "DF (site)", a header block (rows vary
// by year, so located by content — the row whose column C resolves to
// "NATUREZA" — not by row number), a month-abbreviation header row right
// after it (JAN..DEZ, column position also read from content, not
// hardcoded — column D is a yearly TOTAL and is skipped), then one row per
// (crime type) with a monthly count per column. Four report sections, only
// three of which are real occurrences:
//   1. C.V.L.I. (lethal violent crimes) — each crime type gets TWO rows,
//      "OCORRÊNCIA" (count) then "VÍTIMA" (victim count) — VÍTIMA rows are
//      skipped entirely (NATUREZA_MAP is keyed on the crime-type label
//      alone, and the OCORRÊNCIA/VÍTIMA rows share the same label, so
//      isVictimRow() checks the adjacent OCORRÊNCIA/VÍTIMA column instead).
//   2. C.C.P. (property crimes) — one row per type, no victim split.
//   3. OUTROS CRIMES (attempted homicide/femicide/latrocínio, rape) — one
//      row per type.
//   4. PRODUTIVIDADE POLICIAL — drugs and weapon possession are real
//      enforcement events (kept); "LOCALIZAÇÃO DE VEÍCULO FURTADO OU
//      ROUBADO" is a recovered-vehicle count, not an incident, and is
//      deliberately absent from NATUREZA_MAP so it's silently skipped like
//      any other unmapped label (same "exhaustive allowlist" convention as
//      SSP-MG/SSP-BA's NATUREZA_MAP, extended here with an explicit
//      exclusion note since this is the one label seen and knowingly left
//      out, not simply unseen).
// Each section also ends with a subtotal row (A column holds "2. TOTAL
// C.C.P." etc., no crime-type label in column C) — these fall through
// NATUREZA_MAP's lookup on their own, same as PRODUTIVIDADE POLICIAL's
// excluded row, no separate handling needed.
//
// DF is a single IBGE municipality (5300108, Brasília — confirmed live via
// servicodados.ibge.gov.br/.../estados/DF/municipios) despite having many
// administrative regions internally, so geoPrecision is MUNICIPALITY with
// a hardcoded IBGE code — no name-matching table needed, unlike every
// other state adapter here.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import {
  forEachRow,
  inflateEntrySync,
  locateZipEntries,
  parseSharedStrings,
  type ZipEntry,
} from "../../xlsx_lite.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const LISTING_PAGE_URL = "https://www.ssp.df.gov.br/dados-por-regiao-administrativa/";
const DF_IBGE_CODE = "5300108";
const YEARS_WINDOW = 2;

// dados-por-regiao-administrativa/ 403s a bare/default HTTP client User-
// Agent, same naive bot filter SSP-MG's dataset page has (mg_ssp.ts) — a
// normal browser UA works fine, confirmed live.
const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

// Filters to the state-wide "DISTRITO FEDERAL" report only — every per-RA
// file is named after its region (20_aguas-claras-N-xlsx, 09_ceilandia-N-
// xlsx, ...), never after the state, so this pattern never matches one.
const STATEWIDE_HREF_RE = /href="([^"]*(?:distrito-federal|balanco-criminal|df-\d{4})[^"]*-xlsx)"/gi;
// The nearest "year label" ending right before the href's enclosing
// <strong> closes — covers both label shapes the live page actually uses
// (see header comment). Searched backward from each href match.
const YEAR_LABEL_RE = /(\d{4})\s*(?:<\/span>){0,3}<\/strong>/g;

interface YearFile {
  year: number;
  url: string;
}

function findStatewideYearFiles(html: string): YearFile[] {
  const files: YearFile[] = [];
  const seenYears = new Set<number>();
  let hrefMatch: RegExpExecArray | null;
  STATEWIDE_HREF_RE.lastIndex = 0;
  while ((hrefMatch = STATEWIDE_HREF_RE.exec(html))) {
    const windowStart = Math.max(0, hrefMatch.index - 700);
    const windowText = html.slice(windowStart, hrefMatch.index);

    let year: number | undefined;
    let yearMatch: RegExpExecArray | null;
    YEAR_LABEL_RE.lastIndex = 0;
    while ((yearMatch = YEAR_LABEL_RE.exec(windowText))) {
      year = Number(yearMatch[1]);
    }
    if (!year || seenYears.has(year)) continue;

    seenYears.add(year);
    const href = hrefMatch[1];
    files.push({ year, url: href.startsWith("http") ? href : `https://www.ssp.df.gov.br${href}` });
  }
  return files;
}

function mostRecentYearFiles(files: YearFile[]): YearFile[] {
  return [...files].sort((a, b) => b.year - a.year).slice(0, YEARS_WINDOW);
}

// crime-type label -> [eventCategory, eventType, severity]. An allowlist,
// not exhaustive by accident: LOCALIZAÇÃO DE VEÍCULO FURTADO OU ROUBADO
// (recovered-vehicle count, not an incident) and every subtotal/section
// label are deliberately absent — see header comment.
const NATUREZA_MAP: Record<string, [string, string, string]> = {
  "HOMICÍDIO": ["VIOLENCE", "homicide", "high"],
  "TENTATIVA DE HOMICÍDIO": ["VIOLENCE", "attempted_homicide", "medium"],
  "FEMINICÍDIO": ["VIOLENCE", "femicide", "high"],
  "TENTATIVA DE FEMINICÍDIO": ["VIOLENCE", "femicide", "high"],
  "LATROCÍNIO": ["VIOLENCE", "homicide", "high"],
  "TENTATIVA DE LATROCÍNIO": ["VIOLENCE", "attempted_homicide", "medium"],
  "LESÃO CORPORAL SEG. DE MORTE": ["VIOLENCE", "homicide", "high"],
  "ESTUPRO": ["VIOLENCE", "sexual_violence", "high"],
  "ESTUPRO DE VULNERÁVEL": ["VIOLENCE", "sexual_violence", "high"],
  "ROUBO A TRANSEUNTE": ["PROPERTY", "robbery", "medium"],
  "ROUBO DE VEÍCULO": ["PROPERTY", "vehicle_robbery", "medium"],
  "ROUBO EM TRANSPORTE COLETIVO": ["PROPERTY", "robbery", "medium"],
  "ROUBO EM COMÉRCIO *": ["PROPERTY", "robbery", "medium"],
  "ROUBO EM RESIDÊNCIA": ["PROPERTY", "robbery", "medium"],
  "FURTO EM VEÍCULO": ["PROPERTY", "vehicle_theft", "low"],
  "TRÁFICO DE DROGAS": ["PUBLIC_SAFETY", "drugs", "medium"],
  "USO E PORTE DE DROGAS": ["PUBLIC_SAFETY", "drugs", "low"],
  "POSSE/PORTE DE ARMA DE FOGO": ["PUBLIC_SAFETY", "weapon", "medium"],
};

const MONTH_MAP: Record<string, number> = {
  "JAN": 1, "FEV": 2, "MAR": 3, "ABR": 4, "MAI": 5, "JUN": 6,
  "JUL": 7, "AGO": 8, "SET": 9, "OUT": 10, "NOV": 11, "DEZ": 12,
};

// The one signal used to find the report's header rows — content-driven,
// not row-number-driven, since row numbers already shifted between the
// 2025 and 2026 files (verified: both real, both otherwise identical
// layout). Column C (index 2) holds this label on the first header row.
const NATUREZA_HEADER = "NATUREZA";
const OCORRENCIA_LABEL = "OCORRÊNCIA";
const VITIMA_LABEL = "VÍTIMA";

async function resolveFirstSheetEntry(
  zipBytes: Uint8Array,
  entries: Map<string, ZipEntry>,
): Promise<ZipEntry | undefined> {
  const workbookEntry = entries.get("xl/workbook.xml");
  const relsEntry = entries.get("xl/_rels/workbook.xml.rels");
  if (!workbookEntry || !relsEntry) return undefined;

  // Not resolveSheetEntry() from xlsx_lite.ts — that matches by sheet
  // NAME via a regex built from the name itself, and this source's real
  // sheet name is "DF (site)": the parentheses would corrupt the regex.
  // Every real file here has exactly one sheet, so resolving "whichever
  // sheet is first" via its r:id sidesteps the name entirely.
  const workbookXml = await inflateEntrySync(zipBytes, workbookEntry);
  const sheetMatch = /<sheet[^>]*r:id="(rId\d+)"/.exec(workbookXml);
  if (!sheetMatch) return undefined;
  const rId = sheetMatch[1];

  const relsXml = await inflateEntrySync(zipBytes, relsEntry);
  const relMatch = new RegExp(`<Relationship Id="${rId}"[^>]*Target="([^"]+)"`).exec(relsXml);
  if (!relMatch) return undefined;

  return entries.get(`xl/${relMatch[1]}`);
}

export class DfAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "DF",
      name: "SSP-DF - Balanço Criminal",
      organisation: "Secretaria de Estado de Segurança Pública e Paz Social do Distrito Federal",
      sourceType: "official",
      sourceUrl: LISTING_PAGE_URL,
      adapterName: "DfAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const pageRes = await fetch(LISTING_PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!pageRes.ok) {
      throw new Error(`SSP-DF listing page request failed: ${pageRes.status}`);
    }
    const html = await pageRes.text();
    const yearFiles = mostRecentYearFiles(findStatewideYearFiles(html));
    if (yearFiles.length === 0) return [];

    const fetchedAt = new Date().toISOString();
    const records: RawSecurityRecord[] = [];
    for (const file of yearFiles) {
      const fileRes = await fetch(file.url, { headers: { "User-Agent": USER_AGENT } });
      if (!fileRes.ok) {
        console.error(`SSP-DF ${file.year} file request failed: ${fileRes.status}`);
        continue;
      }
      records.push({
        sourceRecordId: `df-balanco-${file.year}`,
        payload: new Uint8Array(await fileRes.arrayBuffer()),
        fetchedAt,
      });
    }
    return records;
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const bytes = record.payload as Uint8Array;
    const entries = locateZipEntries(bytes);

    const sheetEntry = await resolveFirstSheetEntry(bytes, entries);
    const sharedStringsEntry = entries.get("xl/sharedStrings.xml");
    if (!sheetEntry || !sharedStringsEntry) return [];

    const sharedStrings = parseSharedStrings(await inflateEntrySync(bytes, sharedStringsEntry));
    const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");

    // Small streaming state machine, driven by row CONTENT rather than row
    // number (see header comment on why): "seeking-year-row" until column
    // C reads "NATUREZA" (that row also carries the report's year, in one
    // of the columns after it); the very next row is the month-abbreviation
    // header; every row after that is data until the sheet ends.
    type State = "seeking-header" | "seeking-months" | "reading-data";
    let state: State = "seeking-header";
    let year: number | undefined;
    let monthColumns: Map<number, number> = new Map();

    const events: SecurityEvent[] = [];

    await forEachRow(bytes, sheetEntry, sharedStrings, (cells) => {
      if (state === "seeking-header") {
        if (cells[2] !== NATUREZA_HEADER) return;
        // The year appears as a plain numeric cell somewhere after column
        // C on this same row (a merged label spanning the month columns).
        for (const cell of cells.slice(3)) {
          const asNumber = Number(cell);
          if (cell && Number.isInteger(asNumber) && asNumber >= 2000 && asNumber <= 2099) {
            year = asNumber;
            break;
          }
        }
        state = "seeking-months";
        return;
      }

      if (state === "seeking-months") {
        monthColumns = new Map();
        cells.forEach((cell, colIndex) => {
          const month = cell ? MONTH_MAP[cell] : undefined;
          if (month) monthColumns.set(colIndex, month);
        });
        state = monthColumns.size > 0 ? "reading-data" : "seeking-header";
        return;
      }

      // state === "reading-data"
      if (!year || monthColumns.size === 0) return;

      const label = cells[2];
      const occVitLabel = cells[1];

      if (occVitLabel === VITIMA_LABEL) {
        // Victim-count row for the crime type just emitted as an
        // OCORRÊNCIA row above — already counted, skip.
        return;
      }

      const mapped = label ? NATUREZA_MAP[label] : undefined;
      if (!mapped) return;
      const [eventCategory, eventType, severity] = mapped;

      for (const [colIndex, month] of monthColumns) {
        const raw = cells[colIndex];
        const count = raw ? Number(raw) : 0;
        if (!Number.isFinite(count) || count <= 0) continue;

        const yearMonth = `${year}-${String(month).padStart(2, "0")}`;
        events.push({
          countryCode: "BR",
          stateCode: "DF",
          cityIbgeCode: DF_IBGE_CODE,
          sourceRecordId: `${DF_IBGE_CODE}-${yearMonth}-${eventType}-${label}`,
          sourceType: "official",
          eventCategory: eventCategory as SecurityEvent["eventCategory"],
          eventType,
          occurredAt: `${yearMonth}-01T00:00:00-03:00`,
          geoPrecision: "MUNICIPALITY",
          locationConfidence: municipalityLocationConfidence,
          city: "Brasília",
          state: "DF",
          occurrenceCount: count,
          severity,
          confidenceScore: computeConfidenceScore({
            reliabilityGrade: "official_confirmed_record",
            locationConfidence: municipalityLocationConfidence,
          }),
        });
      }
    });

    return events;
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const pageRes = await fetch(LISTING_PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!pageRes.ok) {
        return { status: "RED", message: `HTTP ${pageRes.status} on listing page` };
      }
      const html = await pageRes.text();
      const yearFiles = findStatewideYearFiles(html);
      if (yearFiles.length === 0) {
        return { status: "RED", message: "No state-wide XLS links found — page markup may have changed" };
      }
      const latestYear = Math.max(...yearFiles.map((f) => f.year));
      return { status: "GREEN", lastDataDate: `${latestYear}-01-01` };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
