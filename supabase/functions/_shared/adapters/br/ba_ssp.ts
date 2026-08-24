// BeeAware Brasil roadmap / Phase 2 — BaAdapter (Bahia, SSP-BA "Morte
// Violenta Intencional no Estado" open data).
//
// Real CKAN dataset, verified live 2026-08-24 via
// https://dados.ba.gov.br/api/3/action/package_search?q=mortes+violentas
// — one static CSV resource, small (324KB, 5174 rows), no auth, no
// browser-UA gate (unlike SSP-MG). Direct download:
// https://dados.ba.gov.br/dataset/70802d99.../download/mortes_violentas_estado.csv
//
// Already pre-aggregated per (municipality, year, month, crime type) with
// a QT_VITIMAS victim count — same shape as RJ-ISP/MG, not per-occurrence
// like PA-SEGUP/ES. Real columns confirmed from the header: ANO_1,
// ID_REGIAO, REGIAO, ID_MUNICIPIO, MUNICIPIO, ANO, MES, GR_NATUREZA,
// QT_VITIMAS. `,`-delimited (not `;` like every other Brazilian adapter
// so far), ISO-8859-1 encoded (confirmed: raw 0xE7 byte for "ç" in
// "Alcobaça" with no UTF-8 continuation byte — genuinely Latin-1, same as
// RJ-ISP). Only 6 distinct GR_NATUREZA values across the whole file — an
// exhaustive direct lookup like SSP-MG's, not a regex matcher.
//
// This dataset is scoped to violent DEATHS specifically ("Morte Violenta
// Intencional") — every category is a fatality by definition (homicide,
// femicide, robbery-resulting-in-death, bodily-harm-resulting-in-death,
// prison homicide, self-defense-flagged homicide), so severity is
// uniformly "high" rather than needing a per-type table.
//
// ID_MUNICIPIO is the real IBGE code with its trailing check digit
// stripped (e.g. "290030" for Acajutiba, full code 2900306) — same
// pattern as SSP-MG's cod_municipio, resolved the same way (a numeric
// prefix match against IBGE's own municipality list).
//
// Whole file (2023-2026, 3 years) is small enough to ingest in full — no
// RJ-ISP/PA-SEGUP-style rolling window needed; the entire CSV is smaller
// than a single month of RS-SSP's file.
//
// NOT REGISTERED in index.ts's eventAdapters yet — dados.ba.gov.br's
// server has a genuinely broken TLS certificate chain, confirmed via
// `openssl s_client -showcerts`: the leaf cert (dados.ba.gov.br) states
// its issuer as "Sectigo Public Server Authentication CA OV R36", but the
// two intermediate certs the server actually sends are unrelated Sectigo
// CAs (Domain Validation / Organization Validation) that don't chain to
// it at all. Not a missing-intermediate case fixable by supplying the
// right cert client-side — the server is presenting the wrong ones
// entirely. curl/browsers tolerate this (cached trust, AIA chasing);
// Deno's stricter TLS stack (what Supabase Edge Functions run on)
// rejects it outright: "invalid peer certificate: UnknownIssuer",
// reproduced live. No HTTP fallback exists either (plain :80 redirects
// straight to :443). A real bug on Bahia's own infrastructure, not
// something to route around from here — this file is otherwise correct
// and ready to register the moment their server's cert chain is fixed.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const PACKAGE_URL = "https://dados.ba.gov.br/api/3/action/package_search?q=mortes+violentas&rows=1";
const IBGE_MUNICIPIOS_URL = "https://servicodados.ibge.gov.br/api/v1/localidades/estados/BA/municipios";

interface CkanResource {
  format: string;
  url: string;
}

interface CkanPackageSearchResponse {
  success: boolean;
  result: { results: { resources: CkanResource[] }[] };
}

async function findCsvUrl(): Promise<string | undefined> {
  const res = await fetch(PACKAGE_URL);
  if (!res.ok) {
    throw new Error(`SSP-BA package search failed: ${res.status}`);
  }
  const data = (await res.json()) as CkanPackageSearchResponse;
  const resources = data.result.results[0]?.resources ?? [];
  return resources.find((r) => r.format === "CSV")?.url;
}

// GR_NATUREZA -> eventType. Every value here is a violent death by
// definition (the dataset's own scope), so severity is uniformly "high"
// rather than tracked per type.
const NATUREZA_MAP: Record<string, string> = {
  "HOMICIDIO DOLOSO": "homicide",
  "FEMINICIDIO": "femicide",
  "ROUBO COM RESULTADO MORTE - (LATROCINIO)": "homicide",
  "LESAO CORPORAL SEGUIDA DE MORTE": "homicide",
  "HOMICIDIO OCORRIDO EM PRESIDIO": "homicide",
  "HOMICIDIO DOLOSO COM INDICIO DE EXCLUDENTE DE ILICITUDE": "homicide",
};

// The source's own natureza text has the same encoding inconsistency
// RS-SSP's municipality names needed accent-stripping for — normalize
// before the NATUREZA_MAP lookup so an accented or non-accented variant
// both resolve, rather than adding every possible accent permutation to
// the map by hand.
function stripAccentsUpper(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().trim();
}

const NORMALIZED_NATUREZA_MAP = new Map(
  Object.entries(NATUREZA_MAP).map(([k, v]) => [stripAccentsUpper(k), v]),
);

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

let municipioPrefixCache: Map<string, string> | undefined;

async function municipioPrefixMap(): Promise<Map<string, string>> {
  if (municipioPrefixCache) return municipioPrefixCache;

  const res = await fetch(IBGE_MUNICIPIOS_URL);
  if (!res.ok) {
    throw new Error(`IBGE BA municipios request failed: ${res.status}`);
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

export class BaAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "BA",
      name: "SSP-BA - Morte Violenta Intencional no Estado",
      organisation: "Secretaria da Segurança Pública do Estado da Bahia",
      sourceType: "official",
      sourceUrl: "https://dados.ba.gov.br/dataset/morte_violenta_estado",
      adapterName: "BaAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const csvUrl = await findCsvUrl();
    if (!csvUrl) return [];

    const csvRes = await fetch(csvUrl);
    if (!csvRes.ok) {
      throw new Error(`SSP-BA CSV request failed: ${csvRes.status}`);
    }
    const bytes = new Uint8Array(await csvRes.arrayBuffer());
    const text = new TextDecoder("iso-8859-1").decode(bytes);

    return [
      {
        sourceRecordId: "morte-violenta-estado",
        payload: text,
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const csvText = record.payload as string;
    const rows = parseCsv(csvText);
    if (rows.length === 0) return [];

    const prefixMap = await municipioPrefixMap();

    // 5 of the 6 GR_NATUREZA values collapse onto the single "homicide"
    // eventType (see NATUREZA_MAP) — a municipality can genuinely have
    // rows for more than one of them in the same month (e.g. both
    // HOMICIDIO DOLOSO and LESAO CORPORAL SEGUIDA DE MORTE), which would
    // otherwise collide on the same sourceRecordId and silently lose one
    // count to the other via last-write-wins. Aggregate by
    // (municipality, month, eventType) first, the same pattern RS-SSP/
    // RJ-ISP use, rather than emitting one event per source row.
    interface AggregateGroup {
      cityIbgeCode: string;
      cityName: string;
      yearMonth: string;
      eventType: string;
      occurrenceCount: number;
    }
    const groups = new Map<string, AggregateGroup>();

    for (const row of rows) {
      const victims = Number(row.QT_VITIMAS);
      if (!Number.isFinite(victims) || victims <= 0) continue;

      const eventType = NORMALIZED_NATUREZA_MAP.get(stripAccentsUpper(row.GR_NATUREZA ?? ""));
      if (!eventType) continue;

      const cityIbgeCode = prefixMap.get(row.ID_MUNICIPIO);
      if (!cityIbgeCode) continue;

      const mes = row.MES?.padStart(2, "0");
      const ano = row.ANO;
      if (!mes || !ano) continue;
      const yearMonth = `${ano}-${mes}`;

      const key = `${cityIbgeCode}|${yearMonth}|${eventType}`;
      const existing = groups.get(key);
      if (existing) {
        existing.occurrenceCount += victims;
      } else {
        groups.set(key, { cityIbgeCode, cityName: row.MUNICIPIO, yearMonth, eventType, occurrenceCount: victims });
      }
    }

    const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");

    return Array.from(groups.values()).map((g) => ({
      countryCode: "BR",
      stateCode: "BA",
      cityIbgeCode: g.cityIbgeCode,
      sourceRecordId: `${g.cityIbgeCode}-${g.yearMonth}-${g.eventType}`,
      sourceType: "official",
      eventCategory: "VIOLENCE",
      eventType: g.eventType,
      occurredAt: `${g.yearMonth}-01T00:00:00-03:00`,
      geoPrecision: "MUNICIPALITY",
      locationConfidence: municipalityLocationConfidence,
      city: g.cityName,
      state: "BA",
      occurrenceCount: g.occurrenceCount,
      severity: "high",
      confidenceScore: computeConfidenceScore({
        reliabilityGrade: "official_confirmed_record",
        locationConfidence: municipalityLocationConfidence,
      }),
    }));
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const csvUrl = await findCsvUrl();
      if (!csvUrl) {
        return { status: "RED", message: "No CSV resource found in SSP-BA package" };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
