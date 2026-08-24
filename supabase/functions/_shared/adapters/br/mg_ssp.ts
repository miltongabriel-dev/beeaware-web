// BeeAware Brasil roadmap / Phase 2 — MgAdapter (Minas Gerais, SSP-MG
// "Crimes Violentos" open data).
//
// Minas Gerais is Brazil's 2nd most populous state, and unlike São Paulo
// (SSP-SP's own open-data listing exists but every resource link resolves
// to an Angular SPA shell with no fetchable file underneath — the exact
// same dead-end shape as SINESP's) MG's data genuinely downloads.
// Verified live on 2026-08-24:
// https://dados.mg.gov.br/dataset/crimes-violentos lists one real static
// CSV per year (2019-2026), e.g. .../download/crimes_violentos_2026.csv —
// but a bare request (no browser-like User-Agent) gets a 403; a normal
// browser UA works fine, no session/cookie/CSRF dance needed (simpler
// than PA-SEGUP's requirement, closer to PRF's).
//
// Format is long/row-per-type, not RJ-ISP's wide/column-per-type: each
// row is one (municipality, month, crime type) combination with a
// `registros` count — including zero-count rows for every combination
// that never occurred (89565 rows for the full 2026 year, but only 5136
// have registros > 0; only nonzero rows become events). Only 15 distinct
// `natureza` values exist across the whole dataset (a genuinely closed
// set, unlike RS-SSP's 281 free-text values) — NATUREZA_MAP below is an
// exhaustive direct lookup, not a priority-ordered regex matcher.
//
// `cod_municipio` is a real win over RJ-ISP/RS-SSP: it's the true IBGE
// municipality code with the trailing check digit stripped (e.g. "310060"
// for Água Boa, whose full code is 3100609) — a numeric prefix match
// against IBGE's own municipality list (fetched once, memoized) resolves
// it exactly, no accent-insensitive name fuzzing like RS-SSP needed.
//
// Tried ingesting all 8 available years (2019-2026) at once first — each
// year's parsed row count is small, but fetch() has to download and hold
// every year's raw CSV text simultaneously before normalize() even
// starts (the adapter interface returns the whole RawSecurityRecord[] in
// one shot), and 8 files at ~7-9MB of text each hit WORKER_RESOURCE_LIMIT
// in production, the same class of ceiling RS-SSP's single ~9MB file hit
// on its own. Scoped down to the 2 most recent years instead — same
// rolling-window compromise RJ-ISP/PA-SEGUP already use, for the same
// reason (source file size vs. this Edge Function's memory budget, not a
// data-quality judgment).

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const DATASET_PAGE_URL = "https://dados.mg.gov.br/dataset/crimes-violentos";
const IBGE_MUNICIPIOS_URL = "https://servicodados.ibge.gov.br/api/v1/localidades/estados/MG/municipios";
// dados.mg.gov.br's CKAN front-end 403s a bare/default HTTP client User-
// Agent — confirmed live: curl with no UA gets 403, the same request with
// a normal browser UA succeeds. Not a WAF challenge/CAPTCHA, just a naive
// bot filter.
const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

const CSV_LINK_PATTERN = /href="(https:\/\/dados\.mg\.gov\.br\/dataset\/[^"]*\/download\/crimes_violentos_(\d{4})\.csv)"/g;
const YEARS_WINDOW = 2;

interface YearFile {
  year: number;
  url: string;
}

function findYearFiles(html: string): YearFile[] {
  const files: YearFile[] = [];
  const seen = new Set<number>();
  for (const match of html.matchAll(CSV_LINK_PATTERN)) {
    const [, url, yearStr] = match;
    const year = Number(yearStr);
    if (seen.has(year)) continue;
    seen.add(year);
    files.push({ year, url });
  }
  return files;
}

function mostRecentYearFiles(files: YearFile[]): YearFile[] {
  return [...files].sort((a, b) => b.year - a.year).slice(0, YEARS_WINDOW);
}

// natureza -> [eventCategory, eventType, severity]. Exhaustive: every
// value confirmed present in the real 2026 file is listed; an unmapped
// value falls through and is skipped (logged) rather than guessed, in
// case the source ever adds a 16th category.
const NATUREZA_MAP: Record<string, [string, string, string]> = {
  "ESTUPRO CONSUMADO": ["VIOLENCE", "sexual_violence", "high"],
  "ESTUPRO TENTADO": ["VIOLENCE", "sexual_violence", "high"],
  "ESTUPRO DE VULNERAVEL CONSUMADO": ["VIOLENCE", "sexual_violence", "high"],
  "ESTUPRO DE VULNERAVEL TENTADO": ["VIOLENCE", "sexual_violence", "high"],
  "HOMICIDIO CONSUMADO (REGISTROS)": ["VIOLENCE", "homicide", "high"],
  "HOMICIDIO TENTADO": ["VIOLENCE", "attempted_homicide", "medium"],
  "FEMINICIDIO CONSUMADO (REGISTROS)": ["VIOLENCE", "femicide", "high"],
  "FEMINICIDIO TENTADO": ["VIOLENCE", "femicide", "high"],
  "SEQUESTRO E CARCERE PRIVADO CONSUMADO": ["VIOLENCE", "kidnapping", "high"],
  "SEQUESTRO E CARCERE PRIVADO TENTADO": ["VIOLENCE", "kidnapping", "medium"],
  "EXTORSAO MEDIANTE SEQUESTRO CONSUMADO": ["VIOLENCE", "kidnapping", "high"],
  "ROUBO CONSUMADO": ["PROPERTY", "robbery", "medium"],
  "ROUBO TENTADO": ["PROPERTY", "robbery", "low"],
  "EXTORSAO CONSUMADO": ["PROPERTY", "extortion", "medium"],
  "EXTORSAO TENTADO": ["PROPERTY", "extortion", "low"],
};

function parseCsvLine(line: string, sep: string): string[] {
  const fields: string[] = [];
  let cur = "";
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inQuotes) {
      if (c === '"') {
        if (line[i + 1] === '"') {
          cur += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cur += c;
      }
    } else if (c === '"') {
      inQuotes = true;
    } else if (c === sep) {
      fields.push(cur);
      cur = "";
    } else {
      cur += c;
    }
  }
  fields.push(cur);
  return fields;
}

function parseCsv(text: string, sep: string): Record<string, string>[] {
  // Strip a leading UTF-8 BOM if present (dados.mg.gov.br's files have
  // one) — left in place, it would corrupt the first header name.
  const clean = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
  const lines = clean.split(/\r?\n/).filter((l) => l.length > 0);
  if (lines.length === 0) return [];
  const header = parseCsvLine(lines[0], sep);
  return lines.slice(1).map((line) => {
    const values = parseCsvLine(line, sep);
    const row: Record<string, string> = {};
    header.forEach((h, i) => {
      row[h] = values[i] ?? "";
    });
    return row;
  });
}

let municipioPrefixCache: Map<string, string> | undefined;

// Maps the source's 6-digit cod_municipio (the real IBGE code with the
// trailing check digit stripped) to the full 7-digit code IbgeAdapter's
// geo_areas rows use, via a prefix match against IBGE's own municipality
// list. Memoized at module scope — normalize() runs once per year-file,
// and this list doesn't change between calls within a single ingestion
// run.
async function municipioPrefixMap(): Promise<Map<string, string>> {
  if (municipioPrefixCache) return municipioPrefixCache;

  const res = await fetch(IBGE_MUNICIPIOS_URL);
  if (!res.ok) {
    throw new Error(`IBGE MG municipios request failed: ${res.status}`);
  }
  const municipios = (await res.json()) as { id: number }[];

  const map = new Map<string, string>();
  for (const m of municipios) {
    const fullCode = String(m.id);
    map.set(fullCode.slice(0, 6), fullCode);
  }
  municipioPrefixCache = map;
  return map;
}

export class MgAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "MG",
      name: "SSP-MG - Crimes Violentos",
      organisation: "Secretaria de Estado de Justiça e Segurança Pública de Minas Gerais",
      sourceType: "official",
      sourceUrl: DATASET_PAGE_URL,
      adapterName: "MgAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const pageRes = await fetch(DATASET_PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!pageRes.ok) {
      throw new Error(`SSP-MG dataset page request failed: ${pageRes.status}`);
    }
    const html = await pageRes.text();
    const yearFiles = mostRecentYearFiles(findYearFiles(html));
    if (yearFiles.length === 0) return [];

    const fetchedAt = new Date().toISOString();
    const records: RawSecurityRecord[] = [];
    for (const file of yearFiles) {
      const csvRes = await fetch(file.url, { headers: { "User-Agent": USER_AGENT } });
      if (!csvRes.ok) {
        console.error(`SSP-MG ${file.year} CSV request failed: ${csvRes.status}`);
        continue;
      }
      records.push({
        sourceRecordId: `crimes_violentos_${file.year}`,
        payload: await csvRes.text(),
        fetchedAt,
      });
    }
    return records;
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const csvText = record.payload as string;
    const rows = parseCsv(csvText, ";");
    if (rows.length === 0) return [];

    const prefixMap = await municipioPrefixMap();
    const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");

    const events: SecurityEvent[] = [];
    for (const row of rows) {
      const registros = Number(row.registros);
      if (!Number.isFinite(registros) || registros <= 0) continue;

      const mapped = NATUREZA_MAP[row.natureza];
      if (!mapped) continue;

      const cityIbgeCode = prefixMap.get(row.cod_municipio);
      if (!cityIbgeCode) continue;

      const mes = row.mes?.padStart(2, "0");
      const ano = row.ano;
      if (!mes || !ano) continue;
      const yearMonth = `${ano}-${mes}`;

      const [eventCategory, eventType, severity] = mapped;

      events.push({
        countryCode: "BR",
        stateCode: "MG",
        cityIbgeCode,
        sourceRecordId: `${cityIbgeCode}-${yearMonth}-${eventType}`,
        sourceType: "official",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        occurredAt: `${yearMonth}-01T00:00:00-03:00`,
        geoPrecision: "MUNICIPALITY",
        locationConfidence: municipalityLocationConfidence,
        city: row.municipio,
        state: "MG",
        occurrenceCount: registros,
        severity,
        confidenceScore: computeConfidenceScore({
          reliabilityGrade: "official_confirmed_record",
          locationConfidence: municipalityLocationConfidence,
        }),
      });
    }

    return events;
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(DATASET_PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on dataset page` };
      }
      const html = await res.text();
      const yearFiles = findYearFiles(html);
      if (yearFiles.length === 0) {
        return { status: "RED", message: "No year CSV links found — page markup may have changed" };
      }
      const latestYear = Math.max(...yearFiles.map((f) => f.year));
      return { status: "GREEN", lastDataDate: `${latestYear}-01-01` };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
