// BeeAware Brasil roadmap / Phase 8 (alphabetical sweep of the remaining
// states) — MsSejuspAdapter (Mato Grosso do Sul, SEJUSP-MS "Crimes
// Violentos Letais Intencionais" microdata).
//
// dados.ms.gov.br is a real, populated CKAN portal (unlike dados.al.gov.br's
// exotic /catalogo/ base path, this one is the plain root API) with a
// dedicated SEJUSP organisation carrying 8 datasets (armas, drogas,
// veículos, ocorrências, desaparecimento/localização de pessoas,
// cumprimento de mandado, and this one). Verified live 2026-08-30:
// https://www.dados.ms.gov.br/datastore/dump/crimes-violentos-letais-intencionais-sejusp
// is a single stable CKAN datastore-dump URL (not split by year the way
// the portal's own drogas/ocorrências datasets are) — 5340 rows spanning
// 2016-01-01 through 2026-08-13, real per-case identifiers (Nº/ANO is
// 100% unique across the file) and a real CÓDIGO IBGE column already
// present on every row (no IBGE-name-matching needed at all, a first for
// this project's CVLI-style adapters — AL/GO/MA all had to resolve city
// text against IBGE's own municipality list).
//
// FATO AGRUPADO is a comma-joined, occasionally duplicated list of EVERY
// legal tag attached to the case (a case can carry several charges), not
// a single closed value the way AL's SUBJETIVIDADE COMPLEMENTAR is. First
// attempt classified by regex over the whole joined string (mirroring
// mt_sesp.ts/rs_ssp.ts's CLASSIFY_RULES shape) and had a real bug: a
// pattern like /HOMICIDIO.*CULPOS/ can match across two DIFFERENT tags in
// the same string (e.g. a case tagged both "HOMICIDIO DOLOSO" *and*,
// separately, "HOMICIDIO CULPOSO NO TRANSITO" from a second charge),
// silently skipping a real homicide row. Splitting FATO AGRUPADO into its
// individual comma-separated tags first found only 56 distinct tags
// total — a genuinely closed, manageable set — so classification here is
// exact tag-set membership, checked in priority order (most specific/
// severe tag wins when a case carries several), not string regex.
//
// One compound rule matters: MS has no distinct LATROCINIO tag — a
// robbery resulting in death is tagged ROUBO + FATOS TIPICOS QUE RESULTAM
// EM MORTE together, so that specific pair is checked before the
// single-tag rules. Verified against the real file (5340 rows, 2016-01
// through 2026-08): with that rule, only 7 rows (0.13%) have no
// classifiable tag at all (either no specific crime named beyond "results
// in death", or a sensitive ABORTO-death edge case) — skipped rather than
// guessed, same as every other adapter here. HOMICIDIO CULPOSO NO
// TRANSITO (a traffic fatality) routes to ROAD_SAFETY/fatal_accident, not
// VIOLENCE — same traffic/non-traffic split sp_ssp.ts's own LESAO
// CORPORAL CULPOSA rules already make for the identical real-world
// distinction.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type { EventCategory } from "../../taxonomy.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const CVLI_CSV_URL =
  "https://www.dados.ms.gov.br/datastore/dump/crimes-violentos-letais-intencionais-sejusp";

function stripAccentsUpper(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().trim();
}

type ClassifyRule = [string, EventCategory, string, "high" | "medium" | "low"];

// Priority-ordered by tag: a case carrying both a lethal tag and a
// lesser one (e.g. HOMICIDIO DOLOSO alongside VIOLENCIA DOMESTICA) is
// classified by the more specific/severe tag, checked first.
const PRIORITY: ClassifyRule[] = [
  ["FEMINICIDIO NA FORMA TENTADA", "VIOLENCE", "attempted_homicide", "medium"],
  ["FEMINICIDIO", "VIOLENCE", "homicide", "high"],
  ["HOMICIDIO DOLOSO NA FORMA TENTADA", "VIOLENCE", "attempted_homicide", "medium"],
  ["HOMICIDIO DOLOSO", "VIOLENCE", "homicide", "high"],
  ["MORTE DECORRENTE DE FATO ATIPICO", "VIOLENCE", "homicide", "high"],
  ["HOMICIDIO CULPOSO NO TRANSITO", "ROAD_SAFETY", "fatal_accident", "high"],
  ["LESAO CORPORAL CULPOSA NO TRANSITO", "ROAD_SAFETY", "accident", "low"],
  ["ESTUPRO DE VULNERAVEL - ART. 217-A", "VIOLENCE", "sexual_violence", "high"],
  ["ESTUPRO", "VIOLENCE", "sexual_violence", "high"],
  ["PEDOFILIA", "VIOLENCE", "sexual_violence", "high"],
  ["SEQUESTRO E CARCERE PRIVADO", "VIOLENCE", "kidnapping", "high"],
  ["TORTURA", "VIOLENCE", "assault", "high"],
  ["VIOLENCIA DOMESTICA", "VIOLENCE", "domestic_violence", "high"],
  ["LESAO CORPORAL GRAVE", "VIOLENCE", "assault", "medium"],
  ["LESAO CORPORAL DOLOSA NA FORMA TENTADA", "VIOLENCE", "assault", "medium"],
  ["LESAO CORPORAL DOLOSA", "VIOLENCE", "assault", "medium"],
  ["MAUS-TRATOS", "VIOLENCE", "domestic_violence", "medium"],
  ["VIAS DE FATO", "VIOLENCE", "assault", "low"],
  ["AMEACA", "PUBLIC_SAFETY", "disturbance", "medium"],
  ["PERSEGUICAO", "PUBLIC_SAFETY", "disturbance", "medium"],
];

function classify(fatoAgrupado: string): [EventCategory, string, "high" | "medium" | "low"] | undefined {
  const tags = new Set(
    stripAccentsUpper(fatoAgrupado)
      .split(",")
      .map((t) => t.trim())
      .filter(Boolean),
  );

  // Latrocínio: MS has no distinct tag for "robbery resulting in death" —
  // it's tagged as this pair together instead (see file header).
  if (tags.has("ROUBO") && tags.has("FATOS TIPICOS QUE RESULTAM EM MORTE")) {
    return ["VIOLENCE", "homicide", "high"];
  }

  for (const [tag, category, type, severity] of PRIORITY) {
    if (tags.has(tag)) return [category, type, severity];
  }
  return undefined;
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

// "DD/MM/YYYY" + "HH:MM:SS" -> ISO datetime in MS's own offset
// (America/Campo_Grande, UTC-04:00, no DST in Brazil since 2019).
function toIsoDateTime(dataDoFato: string, horaDoFato: string): string | undefined {
  const parts = dataDoFato.split("/");
  if (parts.length !== 3) return undefined;
  const [dd, mm, yyyy] = parts;
  if (!dd || !mm || !yyyy) return undefined;
  const time = /^\d{2}:\d{2}:\d{2}$/.test(horaDoFato) ? horaDoFato : "00:00:00";
  return `${yyyy}-${mm}-${dd}T${time}-04:00`;
}

export class MsSejuspAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "MS",
      name: "SEJUSP-MS - Crimes Violentos Letais Intencionais",
      organisation: "Secretaria de Estado de Justiça e Segurança Pública de Mato Grosso do Sul",
      sourceType: "official",
      sourceUrl: "https://www.dados.ms.gov.br/dataset/crimes-violentos-letais-intencionais-sejusp",
      adapterName: "MsSejuspAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "weekly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(CVLI_CSV_URL);
    if (!res.ok) {
      throw new Error(`SEJUSP-MS CVLI CSV request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "ms-sejusp-cvli",
        payload: await res.text(),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const csvText = record.payload as string;
    const rows = parseCsv(csvText);
    if (rows.length === 0) return [];

    const locationConfidence = defaultLocationConfidence("MUNICIPALITY");
    const confidenceScore = computeConfidenceScore({
      reliabilityGrade: "official_confirmed_record",
      locationConfidence,
    });

    const events: SecurityEvent[] = [];
    for (const row of rows) {
      const numAno = row["Nº/ANO"];
      if (!numAno) continue;

      const classified = classify(row["FATO AGRUPADO"] ?? "");
      if (!classified) continue;
      const [eventCategory, eventType, severity] = classified;

      const occurredAt = toIsoDateTime(row["DATA DO FATO"], row["HORA DO FATO"]);
      if (!occurredAt) continue;

      const cityIbgeCode = row["CÓDIGO IBGE"];
      if (!cityIbgeCode) continue;

      const bairro = row["BAIRRO"];

      events.push({
        countryCode: "BR",
        stateCode: "MS",
        cityIbgeCode,
        sourceRecordId: numAno,
        sourceType: "official",
        eventCategory,
        eventType,
        originalCategory: row["FATO"],
        occurredAt,
        geoPrecision: "MUNICIPALITY",
        locationConfidence,
        neighborhood: bairro && bairro.trim() !== "" ? bairro : undefined,
        city: row["MUNICÍPIO"],
        state: "MS",
        occurrenceCount: 1,
        severity,
        confidenceScore,
      });
    }

    return events;
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(CVLI_CSV_URL);
      if (!res.ok) {
        return { status: "RED", message: `CVLI CSV request failed: ${res.status}` };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
