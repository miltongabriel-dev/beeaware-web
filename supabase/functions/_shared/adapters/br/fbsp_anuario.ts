// BeeAware Brasil roadmap — FbspAnuarioAdapter (Fórum Brasileiro de
// Segurança Pública, Anuário Brasileiro de Segurança Pública).
//
// Fills a real gap: 18 of Brazil's 27 states/DF had zero security_events
// coverage before this one (RO, AC, AM, RR, AP, TO, MA, PI, CE, RN, PB, PE,
// SE, PR, SC, MS, GO, DF) — every other BR adapter is either a single state
// (RJ, RS, MG, ES, AL, MT) or one city (PA/SEGUP, Belém only), and
// PRF/RENAEST are national but road-safety only. Investigated (and
// rejected) SSP-SP as a per-occurrence source first: dadosabertos.sp.gov.br
// only links back to the human-facing dashboard pages (no real file URLs),
// and an academic project (SPSafe, USP) documents there being no public
// API at all — they had to script mouse clicks (PyAutoGUI) to scrape it.
// SEGUP-PA's own dashboard (sistemas.segup.pa.gov.br) is a Power BI
// "publish to web" embed, same dead end.
//
// This source is coarser than any of the point/municipality adapters —
// state-level ANNUAL totals, not per-occurrence, not even per-municipality
// — but it's the FBSP's own yearly compilation from those same state
// secretariats (see the "Fonte" row inside T01 itself), republished in one
// consistent, comparable table instead of 27 separate portals in 27
// different formats. And unlike PA-SEGUP or SSP-SP, it's a plain,
// unauthenticated, directly downloadable file — no session/CSRF dance, no
// dashboard wall.
//
// Verified live on 2026-08-25: the URL below returned 200 OK, 1,416,758
// bytes, content-type application/vnd.openxmlformats-officedocument.
// spreadsheetml.sheet — a genuine XLSX, confirmed by opening it (not
// guessed from the download page). Sheet "T01" ("Mortes Violentas
// Intencionais — Brasil e Unidades da Federação — 2024-2025") is a clean
// merged-header table: one row per UF (all 26 states + DF, plus a "Brasil"
// total row that this adapter skips) with 2024 and 2025 absolute counts
// for Homicídio Doloso, Latrocínio, Lesão Corporal Seguida de Morte, and
// Morte Decorrente de Intervenção Policial — column positions confirmed by
// reading the real file with openpyxl, not guessed from a rendered
// preview. "-" cells mean "Fenômeno Inexistente" (the sheet's own legend)
// and are treated as a real, reported zero, not a missing value.
//
// Scope is deliberately narrow, same reasoning as every other adapter
// here: only T01 is parsed, not the ~95 other sheets this workbook has
// (property crime, missing persons, phone theft, police victimisation,
// etc.) — a real follow-up, not attempted here. Every row this produces is
// geo_precision: 'STATE', the coarsest tier besides COUNTRY —
// nearby_security_events already excludes anything coarser than STREET, so
// this can never render as a map pin. It's meant for a future state-level
// choropleth (not built yet — needs UF polygon geometry in geo_areas,
// which IbgeAdapter only fetches at municipality level today) or aggregate
// scoring, not immediate map display.
//
// Annual data has no real day/month — occurredAt is set to Jan 1 of the
// reported year, a deliberate anchor (not a claim about when in the year
// the deaths happened), same spirit as other adapters normalizing an
// imprecise date rather than inventing false precision.
//
// Latrocínio and Lesão Corporal Seguida de Morte both normalize to
// eventType "homicide" — same convention pa_segup.ts already uses for the
// same two crime labels (a violent death is a violent death, regardless of
// the legal name for how it happened). Each keeps its own sourceRecordId
// (state+year+original label) so the three death-cause columns for the
// same state/year don't collide and silently overwrite each other under
// runEventAdapter's dedupe-by-sourceRecordId step.

import * as XLSX from "https://esm.sh/xlsx@0.18.5";
import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const XLSX_URL = "https://forumseguranca.org.br/wp-content/uploads/2026/07/anuario-2026.xlsx";
const SOURCE_PAGE_URL = "https://forumseguranca.org.br/publicacoes/anuario-brasileiro-de-seguranca-publica/";
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";
const SHEET_NAME = "T01";

// Full name as it appears in T01 (footnote markers like " (4)"/" (5)"
// already stripped by the caller) -> 2-letter UF code. Standard, stable
// mapping — Brazil's 26 states + DF don't get renamed.
const UF_CODES: Record<string, string> = {
  "Acre": "AC",
  "Alagoas": "AL",
  "Amapá": "AP",
  "Amazonas": "AM",
  "Bahia": "BA",
  "Ceará": "CE",
  "Distrito Federal": "DF",
  "Espírito Santo": "ES",
  "Goiás": "GO",
  "Maranhão": "MA",
  "Mato Grosso": "MT",
  "Mato Grosso do Sul": "MS",
  "Minas Gerais": "MG",
  "Pará": "PA",
  "Paraíba": "PB",
  "Paraná": "PR",
  "Pernambuco": "PE",
  "Piauí": "PI",
  "Rio de Janeiro": "RJ",
  "Rio Grande do Norte": "RN",
  "Rio Grande do Sul": "RS",
  "Rondônia": "RO",
  "Roraima": "RR",
  "Santa Catarina": "SC",
  "São Paulo": "SP",
  "Sergipe": "SE",
  "Tocantins": "TO",
};

// Column index (0-based, matching XLSX.utils.sheet_to_json's {header: 1}
// array-of-arrays output) -> what that column holds. Confirmed against the
// real sheet: col 0 is the UF name; 1/2 = Homicídio Doloso 2024/2025;
// 3/4 = Latrocínio; 5/6 = Lesão Corporal Seguida de Morte; 9/10 = Morte
// Decorrente de Intervenção Policial. Columns 7/8 (Policiais Vítimas de
// CVLI) and 11+ (MVI totals, rates, % variation) are derived/summary
// columns already covered by summing the four counted here, or aren't
// per-state occurrence counts at all — not re-derived here to avoid double
// counting.
const COLUMNS: Array<{ col: number; year: number; eventType: string; label: string }> = [
  { col: 1, year: 2024, eventType: "homicide", label: "Homicídio Doloso" },
  { col: 2, year: 2025, eventType: "homicide", label: "Homicídio Doloso" },
  { col: 3, year: 2024, eventType: "homicide", label: "Latrocínio" },
  { col: 4, year: 2025, eventType: "homicide", label: "Latrocínio" },
  { col: 5, year: 2024, eventType: "homicide", label: "Lesão Corporal Seguida de Morte" },
  { col: 6, year: 2025, eventType: "homicide", label: "Lesão Corporal Seguida de Morte" },
  { col: 9, year: 2024, eventType: "police_intervention", label: "Morte Decorrente de Intervenção Policial" },
  { col: 10, year: 2025, eventType: "police_intervention", label: "Morte Decorrente de Intervenção Policial" },
];

const COMBINING_DIACRITICS = new RegExp("[\\u0300-\\u036f]", "g");

function slug(s: string): string {
  return s
    .normalize("NFD")
    .replace(COMBINING_DIACRITICS, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

export class FbspAnuarioAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      name: "Anuário Brasileiro de Segurança Pública (FBSP) — Mortes Violentas Intencionais",
      organisation: "Fórum Brasileiro de Segurança Pública",
      sourceType: "official",
      sourceUrl: SOURCE_PAGE_URL,
      adapterName: "FbspAnuarioAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "yearly", // the Anuário itself is an annual publication
    };
  }

  async fetch(): Promise<RawSecurityRecord[]> {
    const res = await fetch(XLSX_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) {
      throw new Error(`FBSP Anuário XLSX request failed: ${res.status}`);
    }
    const bytes = new Uint8Array(await res.arrayBuffer());
    return [
      {
        sourceRecordId: "anuario-2026-t01",
        payload: bytes,
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const bytes = record.payload as Uint8Array;
    const workbook = XLSX.read(bytes, { type: "array" });
    const sheet = workbook.Sheets[SHEET_NAME];
    if (!sheet) return Promise.resolve([]);

    const rows = XLSX.utils.sheet_to_json(sheet, { header: 1, defval: null }) as unknown[][];
    const events: SecurityEvent[] = [];
    const stateConfidence = defaultLocationConfidence("STATE");

    for (const row of rows) {
      const rawName = row[0];
      if (typeof rawName !== "string") continue;
      const name = rawName.replace(/\s*\(\d+\)\s*$/, "").trim();
      const ufCode = UF_CODES[name];
      if (!ufCode) continue; // "Brasil" total row, footnotes, blank rows — not a state

      for (const { col, year, eventType, label } of COLUMNS) {
        const raw = row[col];
        const count = typeof raw === "number" ? raw : raw === "-" ? 0 : null;
        if (count == null) continue;

        events.push({
          countryCode: "BR",
          stateCode: ufCode,
          sourceRecordId: `${ufCode}-${year}-${slug(label)}`,
          sourceType: "official",
          eventCategory: "VIOLENCE",
          eventType,
          originalCategory: label,
          occurredAt: `${year}-01-01T00:00:00-03:00`,
          geoPrecision: "STATE",
          locationConfidence: stateConfidence,
          state: name,
          occurrenceCount: count,
          severity: "high", // every column here counts a violent death
          confidenceScore: computeConfidenceScore({
            reliabilityGrade: "official_confirmed_record",
            locationConfidence: stateConfidence,
          }),
        });
      }
    }

    return Promise.resolve(events);
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(XLSX_URL, { method: "HEAD", headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on XLSX URL` };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
