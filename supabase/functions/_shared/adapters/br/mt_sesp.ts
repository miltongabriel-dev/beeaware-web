// BeeAware Brasil roadmap / Phase 2 — MtAdapter (Mato Grosso, SESP-MT
// "Registros de Ocorrências com Vítimas Mulheres" open data).
//
// Real CKAN dataset, verified live 2026-08-24 via
// https://dadosabertos.mt.gov.br/api/3/action/package_search?q=ocorrencias+mulheres
// — package "registros-de-ocorrencias-mulheres-mt" (org SESP-MT), 8 real
// XLSX resources, one per year (2019-2026), named `ocorrencias_{year}.xlsx`.
// Current year's file (2026, partial): HTTP 200, 646934 bytes, 13515 rows.
// No password/session/CSRF/browser-UA gate — a plain public download, same
// ease as SSP-BA/AL.
//
// This dataset was the ONLY viable one found after checking PR, SC, PE, CE,
// GO, DF and AM — every other candidate was either WAF-blocked (PR, CE),
// only published PDF bulletins (PR, SC, GO), had an unreachable CKAN/portal
// (PE, DF, AM), or had no real crime-data package at all (GO). See this
// investigation's own notes (not committed to the repo) for the full trail.
//
// Genuinely narrower scope than every other adapter so far: every row is an
// occurrence with a FEMALE VICTIM specifically (Lei Maria da Penha and
// related statutes) — not general crime. Confirmed no broader dataset
// exists on this portal (searched "roubo", "furto", "cvli", 0 results).
// This is a real, disclosed limitation: MT rows never populate homicide
// (so historical_safety()'s national comparison is unaffected), and the
// app's coverage-disclaimer copy (lib/backend/location_coverage.dart) says
// so explicitly wherever MT is shown, rather than presenting it as
// equivalent-scope coverage to RJ/MG/ES/AL/RS.
//
// Real header row (Sheet name "Dados"), confirmed from the live file:
// natureza_ocorrencia, ano_fato, mes_fato, data_fato, idade, faixa_etaria,
// cor, sexo, risp_geral, municipio_fato, tipo_local_fato. No unique-ID
// column (same composite-fingerprint approach as ES-SESP/PA-SEGUP) and no
// coordinates/bairro (geoPrecision MUNICIPALITY, same as RJ-ISP/AL/RS).
// municipio_fato is plain-text municipality name — 141 distinct values in
// the real file, matching MT's actual municipality count exactly, so the
// same accent-insensitive name join used by AL/RS should resolve cleanly.
// data_fato is a genuine Excel day-serial (e.g. 46036), not a shared
// string — same EXCEL_EPOCH_MS conversion as ES-SESP.
//
// 24 distinct natureza_ocorrencia values in the real file — small and
// closed enough (like AL's 6 or ES's 2) to map exhaustively, but each
// value is the FULL LEGAL TEXT of the statute (not a short label), so
// CLASSIFY_RULES below matches on a distinctive keyword substring per
// value rather than an exact-string lookup — same shape as RS-SSP's
// keyword classifier, but covering 100% of real values (not RS's 59.9%),
// since this closed set was fully enumerated and inspected, not sampled.
// category/type choices reuse RS-SSP's own precedent where the same real-
// world concept appears in both sources (MEDIDA PROTETIVA/VIOLENCIA
// PSICOLOGICA -> VIOLENCE/domestic_violence; AMEACA/PERSEGUICAO ->
// PUBLIC_SAFETY/disturbance) for consistency across the app's taxonomy;
// genuinely new concepts here (defamation, hate speech, cybercrime,
// trespass, document suppression, sexual harassment) get new eventType
// strings, matching this codebase's own stated design (taxonomy.ts: "the
// list grows with every new state source").
//
// A real, unrelated bug in the shared XLSX reader was found and fixed
// while building this adapter: this file's cell markup orders the style
// attribute before the type attribute (`s="4" t="s"`), which the old
// xlsx_lite.ts buildCellRegex()/parseRowCells() silently mis-parsed as an
// untyped (raw-value) cell instead of resolving it through sharedStrings —
// see xlsx_lite.ts's own header for the fix and verification.
//
// Scope: only the current (highest-year) file per scheduled run, like
// RS-SSP's "pick the newest linked file" pattern — a single year's ~13-30k
// rows is the same order of magnitude as AL's 21294-row/2.5MB file (which
// needed no special streaming), so plain forEachRow() is used, not RS-
// SSP's heavier chunked-decompression machinery (that was needed for RS's
// 439400-row/95MB-decompressed file, a very different scale). Older years
// (2019-2025) are a real, deliberately-deferred backfill — same "start
// scoped, widen later once proven safe" discipline as PA-SEGUP's
// fetchAndNormalizeMonth.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import { forEachRow, locateZipEntries, parseSharedStrings, inflateEntrySync, resolveSheetEntry } from "../../xlsx_lite.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const PACKAGE_SEARCH_URL =
  "https://dadosabertos.mt.gov.br/api/3/action/package_search?q=ocorrencias+mulheres&rows=10";
const IBGE_MUNICIPIOS_URL = "https://servicodados.ibge.gov.br/api/v1/localidades/estados/MT/municipios";
const SHEET_NAME = "Dados";

interface CkanResource {
  name: string;
  format: string;
  url: string;
}

interface CkanPackageSearchResponse {
  success: boolean;
  result: { results: { name: string; resources: CkanResource[] }[] };
}

const RESOURCE_YEAR_PATTERN = /ocorrencias_(\d{4})\.xlsx/i;

async function findLatestResourceUrl(): Promise<string | undefined> {
  const res = await fetch(PACKAGE_SEARCH_URL);
  if (!res.ok) {
    throw new Error(`SESP-MT package search failed: ${res.status}`);
  }
  const data = (await res.json()) as CkanPackageSearchResponse;
  const pkg = data.result.results.find((p) => p.name === "registros-de-ocorrencias-mulheres-mt");
  if (!pkg) return undefined;

  let best: { year: number; url: string } | undefined;
  for (const r of pkg.resources) {
    const match = RESOURCE_YEAR_PATTERN.exec(r.name);
    if (!match) continue;
    const year = Number(match[1]);
    if (!best || year > best.year) best = { year, url: r.url };
  }
  return best?.url;
}

// Same Excel day-serial epoch as ES-SESP (1899-12-30, Lotus 1-2-3's
// fictitious 1900 leap day). Confirmed against the real file: serial 46036
// in row 2 falls in 2026, consistent with the "ocorrencias_2026" file.
const EXCEL_EPOCH_MS = Date.UTC(1899, 11, 30);
const MS_PER_DAY = 86_400_000;

function excelSerialToIsoDate(serial: string | undefined): string | undefined {
  const n = Number(serial);
  if (!Number.isFinite(n) || n <= 0) return undefined;
  return new Date(EXCEL_EPOCH_MS + n * MS_PER_DAY).toISOString().slice(0, 10);
}

function stripAccentsUpper(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().trim();
}

type ClassifyRule = [RegExp, "VIOLENCE" | "PUBLIC_SAFETY", string, "high" | "medium" | "low"];

// Priority-ordered — see file header for why order matters (more specific
// multi-keyword rules before the generic substrings they'd otherwise be
// caught by, e.g. "INJURIA REAL"/"INJURIA RACIAL" before plain "INJURIA").
// Verified this covers all 24 real distinct values with none falling
// through unmapped.
const CLASSIFY_RULES: ClassifyRule[] = [
  [/INJURIA REAL|LESAO CORPORAL/, "VIOLENCE", "assault", "medium"],
  [/ESTUPRO|CENA DE NUDEZ/, "VIOLENCE", "sexual_violence", "high"],
  [/IMPORTUNACAO SEXUAL|ASSEDIO SEXUAL/, "VIOLENCE", "sexual_harassment", "medium"],
  [/MEDIDAS PROTETIVAS/, "VIOLENCE", "domestic_violence", "high"],
  [/DANO EMOCIONAL|MAUS TRATOS/, "VIOLENCE", "domestic_violence", "medium"],
  [/CARGO ELETIVO|VIOLENCIA POLITICA/, "PUBLIC_SAFETY", "disturbance", "medium"],
  [/AMEACA|PERSEGUICAO/, "PUBLIC_SAFETY", "disturbance", "medium"],
  [/INJURIA RACIAL/, "PUBLIC_SAFETY", "hate_speech", "low"],
  [/CALUNIA|DIFAMACAO|INJURIA/, "PUBLIC_SAFETY", "defamation", "low"],
  [/DISPOSITIVO INFORMATICO/, "PUBLIC_SAFETY", "cybercrime", "low"],
  [/DOMICILIO/, "PUBLIC_SAFETY", "trespass", "low"],
  [/SUPRESSAO DE DOCUMENTO/, "PUBLIC_SAFETY", "document_suppression", "low"],
];

type EventCategory = "VIOLENCE" | "PUBLIC_SAFETY";

function classify(natureza: string): [EventCategory, string, "high" | "medium" | "low"] | undefined {
  const n = stripAccentsUpper(natureza);
  for (const [pattern, category, type, severity] of CLASSIFY_RULES) {
    if (pattern.test(n)) return [category, type, severity];
  }
  return undefined;
}

let municipioNameCache: Map<string, string> | undefined;

async function municipioNameMap(): Promise<Map<string, string>> {
  if (municipioNameCache) return municipioNameCache;

  const res = await fetch(IBGE_MUNICIPIOS_URL);
  if (!res.ok) {
    throw new Error(`IBGE MT municipios request failed: ${res.status}`);
  }
  const municipios = (await res.json()) as { id: number; nome: string }[];
  municipioNameCache = new Map(municipios.map((m) => [stripAccentsUpper(m.nome), String(m.id)]));
  return municipioNameCache;
}

export class MtAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "MT",
      name: "SESP-MT - Registros de Ocorrências com Vítimas Mulheres",
      organisation: "Secretaria de Estado de Segurança Pública de Mato Grosso",
      sourceType: "official",
      sourceUrl: "https://dadosabertos.mt.gov.br/dataset/registros-de-ocorrencias-mulheres-mt",
      adapterName: "MtAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const fileUrl = await findLatestResourceUrl();
    if (!fileUrl) return [];

    const fileRes = await fetch(fileUrl);
    if (!fileRes.ok) {
      throw new Error(`SESP-MT file request failed: ${fileRes.status}`);
    }

    return [
      {
        sourceRecordId: fileUrl,
        payload: new Uint8Array(await fileRes.arrayBuffer()),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const bytes = record.payload as Uint8Array;
    const entries = locateZipEntries(bytes);

    const sheetEntry = await resolveSheetEntry(bytes, entries, SHEET_NAME);
    const sharedStringsEntry = entries.get("xl/sharedStrings.xml");
    if (!sheetEntry || !sharedStringsEntry) return [];

    const sharedStrings = parseSharedStrings(await inflateEntrySync(bytes, sharedStringsEntry));
    const municipioToIbgeCode = await municipioNameMap();

    // Column layout confirmed against the real file's header row (row 1):
    // natureza_ocorrencia, ano_fato, mes_fato, data_fato, idade,
    // faixa_etaria, cor, sexo, risp_geral, municipio_fato, tipo_local_fato.
    const COL = { natureza: 0, dataFato: 3, idade: 4, faixaEtaria: 5, cor: 6, sexo: 7, municipio: 9 };

    const events: SecurityEvent[] = [];
    const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");
    let rowIndex = 0;

    await forEachRow(bytes, sheetEntry, sharedStrings, (cells) => {
      rowIndex++;
      if (rowIndex === 1) return; // header row

      const natureza = cells[COL.natureza];
      const mapped = natureza ? classify(natureza) : undefined;
      if (!mapped) return;
      const [eventCategory, eventType, severity] = mapped;

      const occurredAt = excelSerialToIsoDate(cells[COL.dataFato]);
      if (!occurredAt) return;

      const municipioFato = cells[COL.municipio] ?? "";
      const cityIbgeCode = municipioToIbgeCode.get(stripAccentsUpper(municipioFato));
      if (!cityIbgeCode) return;

      const idade = cells[COL.idade] ?? "";
      const faixaEtaria = cells[COL.faixaEtaria] ?? "";
      const cor = cells[COL.cor] ?? "";
      const sexo = cells[COL.sexo] ?? "";

      events.push({
        countryCode: "BR",
        stateCode: "MT",
        cityIbgeCode,
        // No unique ID column in the source — same composite-fingerprint
        // approach as ES-SESP/PA-SEGUP, dedup already handled generically
        // by runEventAdapter's batch-upsert dedup.
        sourceRecordId: `${natureza}|${municipioFato}|${occurredAt}|${idade}|${faixaEtaria}|${cor}|${sexo}`,
        sourceType: "official",
        eventCategory,
        eventType,
        occurredAt: `${occurredAt}T00:00:00-03:00`,
        geoPrecision: "MUNICIPALITY",
        locationConfidence: municipalityLocationConfidence,
        city: municipioFato,
        state: "MT",
        occurrenceCount: 1,
        severity,
        confidenceScore: computeConfidenceScore({
          reliabilityGrade: "official_confirmed_record",
          locationConfidence: municipalityLocationConfidence,
        }),
      });
    });

    return events;
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const fileUrl = await findLatestResourceUrl();
      if (!fileUrl) {
        return { status: "RED", message: "No ocorrencias_{year}.xlsx resource found in SESP-MT package" };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
