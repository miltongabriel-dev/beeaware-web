// BeeAware Brasil roadmap / Phase 2 — AlAdapter (Alagoas, SEDS "CVLI"
// per-occurrence microdata).
//
// Real CKAN dataset, verified live 2026-08-24 — but on a non-standard API
// base path: dados.al.gov.br's CKAN root is at /catalogo/, not /, so the
// usual package_search/package_show endpoints 404 without that prefix
// (confirmed: https://dados.al.gov.br/api/3/action/... 404s,
// https://dados.al.gov.br/catalogo/api/3/action/... works). Dataset
// "cvli-2012-a-2023-base-microdados" has one real CSV resource
// (2.5MB, 21294 rows, 2012 through June 2026) alongside a separate
// PDF-bulletin dataset (not usable for ingestion, skipped).
//
// This is CVLI: "Crime Violento Letal Intencional" — every row is
// already scoped to an intentional lethal violent crime, same framing as
// SSP-BA's "Morte Violenta Intencional" dataset. SUBJETIVIDADE is always
// literally "CVLI" (not a useful classifier); SUBJETIVIDADE COMPLEMENTAR
// carries the real 6-value closed set (Homicídio, Feminicídio,
// Infanticídio, Roubo com Resultado Morte, Lesão Corporal Seguida de
// Morte, Estupro com Resultado Morte) — COMPLEMENTAR_MAP below is
// exhaustive.
//
// Real win over every other Brazilian adapter so far: ID_CONTROLE is a
// genuine unique per-row identifier (46, 47, 48, ...) — sourceRecordId
// doesn't need PA-SEGUP/ES's composite-fingerprint approach at all.
//
// No coordinates (unlike ES) — only CIDADE DO FATO (city, plain text) and
// BAIRRO DO FATO (neighbourhood, plain text), so geoPrecision is
// MUNICIPALITY, resolved via the same accent-insensitive name match
// RS-SSP uses against IBGE's own municipality list (no numeric code given
// here, unlike SSP-MG/SSP-BA). AL has exactly 102 municipalities per IBGE,
// matching the 102 distinct city names found in the real file — good
// coverage to expect from the match.
//
// Whole file (21294 rows, 2.5MB) is small enough to ingest in full, same
// as SSP-BA — no rolling-window scoping needed.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const PACKAGE_SEARCH_URL = "https://dados.al.gov.br/catalogo/api/3/action/package_search?q=cvli&rows=5";
const IBGE_MUNICIPIOS_URL = "https://servicodados.ibge.gov.br/api/v1/localidades/estados/AL/municipios";

interface CkanResource {
  format: string;
  url: string;
  name: string;
}

interface CkanPackageSearchResponse {
  success: boolean;
  result: { results: { name: string; resources: CkanResource[] }[] };
}

async function findCsvUrl(): Promise<string | undefined> {
  const res = await fetch(PACKAGE_SEARCH_URL);
  if (!res.ok) {
    throw new Error(`SEDS-AL package search failed: ${res.status}`);
  }
  const data = (await res.json()) as CkanPackageSearchResponse;
  const microdadosPackage = data.result.results.find((p) => p.name.includes("microdados"));
  return microdadosPackage?.resources.find((r) => r.format === "CSV")?.url;
}

// SUBJETIVIDADE COMPLEMENTAR -> eventType. Exhaustive: all 6 real values
// confirmed present in the live file. Every category here is already a
// fatality by this dataset's own scope (CVLI), so severity is uniformly
// "high" — same reasoning as SSP-BA's "Morte Violenta Intencional".
const COMPLEMENTAR_MAP: Record<string, string> = {
  "Homicídio": "homicide",
  "Feminicídio": "femicide",
  "Infanticídio": "infanticide",
  "Roubo com Resultado Morte": "homicide",
  "Lesão Corporal Seguida de Morte": "homicide",
  "Estupro com Resultado Morte": "sexual_violence",
};

function stripAccentsUpper(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().trim();
}

const NORMALIZED_COMPLEMENTAR_MAP = new Map(
  Object.entries(COMPLEMENTAR_MAP).map(([k, v]) => [stripAccentsUpper(k), v]),
);

// DD/MM/YYYY -> ISO date (YYYY-MM-DD).
function toIsoDate(dataDoFato: string): string | undefined {
  const parts = dataDoFato.split("/");
  if (parts.length !== 3) return undefined;
  const [dd, mm, yyyy] = parts;
  if (!dd || !mm || !yyyy) return undefined;
  return `${yyyy}-${mm}-${dd}`;
}

function parseCsvLine(line: string): string[] {
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
    } else if (c === ",") {
      fields.push(cur);
      cur = "";
    } else {
      cur += c;
    }
  }
  fields.push(cur);
  return fields;
}

function parseCsv(text: string): Record<string, string>[] {
  const lines = text.split(/\r?\n/).filter((l) => l.length > 0);
  if (lines.length === 0) return [];
  const header = parseCsvLine(lines[0]);
  return lines.slice(1).map((line) => {
    const values = parseCsvLine(line);
    const row: Record<string, string> = {};
    header.forEach((h, i) => {
      row[h] = values[i] ?? "";
    });
    return row;
  });
}

let municipioNameCache: Map<string, string> | undefined;

async function municipioNameMap(): Promise<Map<string, string>> {
  if (municipioNameCache) return municipioNameCache;

  const res = await fetch(IBGE_MUNICIPIOS_URL);
  if (!res.ok) {
    throw new Error(`IBGE AL municipios request failed: ${res.status}`);
  }
  const municipios = (await res.json()) as { id: number; nome: string }[];
  municipioNameCache = new Map(municipios.map((m) => [stripAccentsUpper(m.nome), String(m.id)]));
  return municipioNameCache;
}

export class AlAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "AL",
      name: "SEDS-AL - CVLI Microdados",
      organisation: "Secretaria de Estado da Segurança Pública de Alagoas",
      sourceType: "official",
      sourceUrl: "https://dados.al.gov.br/catalogo/dataset/cvli-2012-a-2023-base-microdados",
      adapterName: "AlAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const csvUrl = await findCsvUrl();
    if (!csvUrl) return [];

    const csvRes = await fetch(csvUrl);
    if (!csvRes.ok) {
      throw new Error(`SEDS-AL CSV request failed: ${csvRes.status}`);
    }

    return [
      {
        sourceRecordId: "cvli-microdados",
        payload: await csvRes.text(),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const csvText = record.payload as string;
    const rows = parseCsv(csvText);
    if (rows.length === 0) return [];

    const nameMap = await municipioNameMap();
    const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");

    const events: SecurityEvent[] = [];
    for (const row of rows) {
      const idControle = row.ID_CONTROLE;
      if (!idControle) continue;

      const eventType = NORMALIZED_COMPLEMENTAR_MAP.get(
        stripAccentsUpper(row["SUBJETIVIDADE COMPLEMENTAR"] ?? ""),
      );
      if (!eventType) continue;

      const occurredAt = toIsoDate(row["DATA DO FATO"]);
      if (!occurredAt) continue;

      const cityIbgeCode = nameMap.get(stripAccentsUpper(row["CIDADE DO FATO"] ?? ""));
      if (!cityIbgeCode) continue;

      const bairro = row["BAIRRO DO FATO"];

      events.push({
        countryCode: "BR",
        stateCode: "AL",
        cityIbgeCode,
        sourceRecordId: idControle,
        sourceType: "official",
        eventCategory: "VIOLENCE",
        eventType,
        occurredAt: `${occurredAt}T00:00:00-03:00`,
        geoPrecision: "MUNICIPALITY",
        locationConfidence: municipalityLocationConfidence,
        neighborhood: bairro && bairro !== "NI" ? bairro : undefined,
        city: row["CIDADE DO FATO"],
        state: "AL",
        occurrenceCount: 1,
        severity: "high",
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
      const csvUrl = await findCsvUrl();
      if (!csvUrl) {
        return { status: "RED", message: "No CSV resource found in SEDS-AL CVLI package" };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
