// BeeAware Brasil roadmap / Phase 8 (second-wave states) — RoSepogAdapter
// (Rondônia, SEPOG/SESDEC "Painel de Segurança Pública" — Observatório do
// Desenvolvimento de RO).
//
// RO was previously documented (see pe_sds.ts's header) as a dead end: a
// real, live dashboard API existed at observatorio.sepog.ro.gov.br, but
// every request replaying the frontend's exact payload shape returned a
// valid, empty {"result":[]} regardless of date range. Re-investigated
// 2026-09-23 — the host itself was unreachable from the environment that
// found this originally, and once it was reachable again the actual bug
// was findable: both filter dropdowns (Município, Natureza) are
// `multiple` Semantic UI selects with an explicit <option value="0">
// Todos</option> sentinel for "no filter" — sending an EMPTY value (what
// the earlier attempt did, reasonably assuming empty = unfiltered) isn't
// the same thing to this backend and returns a valid-but-empty result.
// Sending municipio=0&natureza=0 (verified live) returns real data.
//
// Two real ASP.NET MVC endpoints, no session/cookie/CSRF token required
// (confirmed: a cold POST with zero prior requests to the site works
// identically to one preceded by a GET) — genuinely simpler to call than
// most sources in this project:
//   - GetDataForTableOcorrenciasIndicadoresPerType with type=
//     "municipio_fato" returns, for the whole state in one call,
//     [rank, municipality_name (lowercase), occurrence_count,
//     population, internal_municipio_id] rows — internal_municipio_id
//     is exactly the same value the Município <select>'s own <option
//     value="..."> uses (verified: Porto Velho is both "652" in this
//     response and in the dropdown), which is what makes the second call
//     below possible without scraping the dropdown's HTML separately.
//   - The same endpoint with type="natureza_fato" and a specific
//     municipio=<id> returns that ONE municipality's own occurrence
//     counts broken down by crime type ([rank, natureza_label, count]).
// tipo is hardcoded "FO_S1" in the page's own JS (no other tipo value
// exists anywhere on this panel) — this is RO's "Fato de Ocorrência"
// (initial police-report) system, not a separate formal-inquérito
// classification. Real, important scope limitation found while mapping
// categories: this dataset's own Natureza filter (851 real options,
// checked directly) has NO "Homicídio Doloso" entry at all — only
// "Homicídio Culposo"/"Homicídio Culposo no Trânsito" (negligent) and
// "Roubo Seguido de Morte - Latrocínio" (robbery-homicide). Intentional
// homicide is evidently tracked in a separate system this panel doesn't
// expose — EVENTO_MAP below does NOT claim a "homicide" mapping for
// anything but latrocínio and death-by-state-agent, unlike every other
// state adapter in this project that has a real "Homicídio Doloso" row
// to map. Don't add one without a real source for it.
//
// Municipality identity: the response gives a name only (no IBGE code),
// resolved against IBGE's own RO municipios list (52 municipalities,
// confirmed count match) the same accent-insensitive way BA-SSP/SINESP
// do — RO has several "X D'Oeste" names, but IBGE and this source both
// use a plain straight apostrophe for them (checked directly), so no
// extra normalization beyond the usual accent-strip/uppercase was
// needed.
//
// fetch() makes ~1 + (municipalities with any activity that month, ≤52)
// HTTP calls — one municipio_fato call to get the full list (and its
// internal ids) for the target month, then one natureza_fato call per
// municipality, fired concurrently via Promise.allSettled (same pattern
// G1NewsAdapter already uses for its 27 concurrent regional-feed
// fetches) rather than a manual concurrency-limiter — a municipality
// whose call fails is skipped, not fatal to the whole run. Scoped to
// the single most recently COMPLETE calendar month only (not a 2-month
// window like SINESP/PRF) to keep the per-run call count and payload
// size predictable.
//
// The full request shape (all 52 concurrent natureza_fato calls plus
// the municipio_fato call, exact same params this code sends) was dry-
// run live 2026-09-23 outside the Edge Function runtime: 52/52 municipal
// requests succeeded in ~5s wall-clock, all 52 municipality names
// matched IBGE with zero misses, and running EVENTO_MAP over the real
// August 2026 response produced 573 municipality×type rows (theft 2045,
// accident 2008, assault 1056, domestic_violence 591, robbery 524,
// sexual_violence 189, drugs 184, fire 164, disturbance 164, emergency
// 100, fatal_accident 41, kidnapping 10, homicide 1 — plausible
// distribution for one state, one month). What that dry run can't
// confirm is this exact .ts file executing inside Supabase's actual
// Deno runtime (module resolution, the shared confidence.ts/types.ts
// imports, a real `supabase functions deploy`) — unlike most adapters
// in this directory, this one hasn't had that specific check yet.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const BASE_URL = "https://observatorio.sepog.ro.gov.br";
const TABLE_ENDPOINT = `${BASE_URL}/SegurancaPublica/GetDataForTableOcorrenciasIndicadoresPerType`;
const IBGE_MUNICIPIOS_URL = "https://servicodados.ibge.gov.br/api/v1/localidades/estados/RO/municipios";
const USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
const TIPO = "FO_S1";

// natureza label -> [category, type]. Deliberate allowlist (same
// philosophy as sinesp.ts's EVENTO_MAP) covering the categories that map
// cleanly onto taxonomy.ts — generic/administrative rows (PERDA OU
// EXTRAVIO, CUMPRIMENTO DE MANDADO/DILIGÊNCIAS, PROCEDIMENTO MIGRADO,
// LOCALIZAÇÃO DE VEÍCULO), honor crimes with no safe bucket (INJÚRIA,
// DIFAMAÇÃO, CALÚNIA), and ambiguous ones (DANO, MAUS-TRATOS,
// CONFLITOS DIVERSOS) are deliberately skipped rather than force-fit.
const EVENTO_MAP: Record<string, [category: string, type: string]> = {
  "ROUBO SEGUIDO DE MORTE - LATROCINIO": ["VIOLENCE", "homicide"],
  "MORTE POR INTERVENCAO DE AGENTE DO ESTADO": ["VIOLENCE", "police_intervention"],
  "ESTUPRO": ["VIOLENCE", "sexual_violence"],
  "ESTUPRO DE VULNERAVEL": ["VIOLENCE", "sexual_violence"],
  "LESAO CORPORAL": ["VIOLENCE", "assault"],
  "LESAO CORPORAL (VIOLENCIA DOMESTICA)": ["VIOLENCE", "domestic_violence"],
  "AMEACA (VIOLENCIA DOMESTICA)": ["VIOLENCE", "domestic_violence"],
  "DESCUMPRIMENTO DE MEDIDAS PROTETIVA DE URGENCIA": ["VIOLENCE", "domestic_violence"],
  "SEQUESTRO E CARCERE PRIVADO": ["VIOLENCE", "kidnapping"],
  "SEQUESTRO E CARCERE PRIVADO (VIOLENCIA DOMESTICA)": ["VIOLENCE", "kidnapping"],
  "SEQUESTRO / CARCERE PRIVADO": ["VIOLENCE", "kidnapping"],
  "EXTORSAO MEDIANTE SEQUESTRO": ["VIOLENCE", "kidnapping"],
  "VIAS DE FATO": ["VIOLENCE", "assault"],
  "FURTO": ["PROPERTY", "theft"],
  "ROUBO": ["PROPERTY", "robbery"],
  "DROGAS - TRAFICO": ["PUBLIC_SAFETY", "drugs"],
  "INCENDIO": ["PUBLIC_SAFETY", "fire"],
  "PERTURBACAO DO TRABALHO OU DO SOSSEGO ALHEIO": ["PUBLIC_SAFETY", "disturbance"],
  "DESAPARECIMENTO DE PESSOA": ["PUBLIC_SAFETY", "emergency"],
  "SINISTRO DE TRANSITO": ["ROAD_SAFETY", "accident"],
  "SINISTRO DE TRANSITO SEM VITIMA": ["ROAD_SAFETY", "accident"],
  "LESAO CORPORAL CULPOSA DE TRANSITO": ["ROAD_SAFETY", "accident"],
  "ACIDENTE DE TRANSITO - AUTO LESAO": ["ROAD_SAFETY", "accident"],
  "ACIDENTE DE TRANSITO COM VITIMA FATAL": ["ROAD_SAFETY", "fatal_accident"],
  "ACIDENTE DE TRANSITO COM VITIMA FATAL PROVOCADO PELA PROPRIA VITIMA": ["ROAD_SAFETY", "fatal_accident"],
  "ACIDENTE DE TRANSITO COM VITIMA FATAL - SOMENTE O CONDUTOR VEICULO": ["ROAD_SAFETY", "fatal_accident"],
  "MORTE ACIDENTAL DE TRANSITO": ["ROAD_SAFETY", "fatal_accident"],
  "HOMICIDIO CULPOSO NO TRANSITO": ["ROAD_SAFETY", "fatal_accident"],
};

function stripAccentsUpper(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().trim();
}

const NORMALIZED_EVENTO_MAP = new Map(
  Object.entries(EVENTO_MAP).map(([k, v]) => [stripAccentsUpper(k), v]),
);

const HIGH_SEVERITY = new Set(["homicide", "police_intervention", "sexual_violence", "kidnapping", "fatal_accident"]);
const LOW_SEVERITY = new Set(["theft", "accident", "disturbance"]);
function severityFor(eventType: string): string {
  if (HIGH_SEVERITY.has(eventType)) return "high";
  if (LOW_SEVERITY.has(eventType)) return "low";
  return "medium";
}

// The most recent COMPLETE calendar month, as "DD/MM/YYYY" start/end —
// the exact format the panel's own calendar widget formats to (see
// SESDEC.initCalendar's formatter in Scripts/site/
// SegurancaPublicaIndicadores.js), confirmed working live.
function targetMonthRange(): { start: string; end: string; yearMonth: string } {
  const now = new Date();
  const firstOfThisMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const lastMonthEnd = new Date(firstOfThisMonth.getTime() - 1);
  const firstOfLastMonth = new Date(Date.UTC(lastMonthEnd.getUTCFullYear(), lastMonthEnd.getUTCMonth(), 1));

  const pad = (n: number) => String(n).padStart(2, "0");
  const fmt = (d: Date) => `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}`;

  return {
    start: fmt(firstOfLastMonth),
    end: fmt(lastMonthEnd),
    yearMonth: `${lastMonthEnd.getUTCFullYear()}-${pad(lastMonthEnd.getUTCMonth() + 1)}`,
  };
}

type TableRow = string[];

// periodo1 needs TWO "periodo_1" keys in the POST body (a start/end
// range, matching the panel's own two-input calendar) — plain
// URLSearchParams.append (not a single set()) is what produces that,
// same "traditional" jQuery array-serialization shape ($.ajax's
// traditional: true option) the page's own JS uses, confirmed live: a
// bracketed/JSON-array encoding of this field silently fails to bind
// server-side and returns a valid-but-empty result, the same failure
// mode the ORIGINAL "empty municipio/natureza" bug produced.
async function postTable(
  type: string,
  municipio: string,
  periodo1: [string, string],
): Promise<TableRow[]> {
  const params = new URLSearchParams();
  params.append("type", type);
  params.append("municipio", municipio);
  params.append("natureza", "0");
  params.append("tipo", TIPO);
  params.append("periodo_1", periodo1[0]);
  params.append("periodo_1", periodo1[1]);

  const res = await fetch(TABLE_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
      "X-Requested-With": "XMLHttpRequest",
      "User-Agent": USER_AGENT,
    },
    body: params.toString(),
  });
  if (!res.ok) {
    throw new Error(`RO-SEPOG table request failed: ${res.status}`);
  }
  const data = (await res.json()) as { result: TableRow[] };
  return data.result ?? [];
}

let municipioMapCache: Map<string, string> | undefined;

async function municipioMap(): Promise<Map<string, string>> {
  if (municipioMapCache) return municipioMapCache;

  const res = await fetch(IBGE_MUNICIPIOS_URL);
  if (!res.ok) {
    throw new Error(`IBGE RO municipios request failed: ${res.status}`);
  }
  const municipios = (await res.json()) as { id: number; nome: string }[];

  const map = new Map<string, string>();
  for (const m of municipios) {
    map.set(stripAccentsUpper(m.nome), String(m.id));
  }
  municipioMapCache = map;
  return map;
}

interface MunicipioPayload {
  municipioId: string;
  municipioName: string;
  yearMonth: string;
  naturezaRows: TableRow[];
}

export class RoSepogAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "RO",
      name: "SEPOG-RO - Painel de Segurança Pública (Observatório do Desenvolvimento de RO)",
      organisation: "Secretaria de Estado do Planejamento, Orçamento e Gestão de Rondônia",
      sourceType: "official",
      sourceUrl: `${BASE_URL}/SegurancaPublica`,
      adapterName: "RoSepogAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const { start, end, yearMonth } = targetMonthRange();
    const fetchedAt = new Date().toISOString();

    // One call, municipio=0 ("Todos"), gets every municipality's own
    // total for the month AND its internal municipio id (row[4]) in one
    // shot — see file header for why that id is exactly the dropdown's
    // own <option value>, avoiding a separate lookup step.
    const municipioRows = await postTable("municipio_fato", "0", [start, end]);

    const settled = await Promise.allSettled(
      municipioRows.map(async (row) => {
        const municipioName = row[1];
        const municipioId = row[4];
        if (!municipioName || !municipioId) throw new Error("malformed municipio_fato row");

        const naturezaRows = await postTable("natureza_fato", municipioId, [start, end]);
        const payload: MunicipioPayload = { municipioId, municipioName, yearMonth, naturezaRows };
        return payload;
      }),
    );

    const records: RawSecurityRecord[] = [];
    for (const result of settled) {
      if (result.status === "fulfilled") {
        records.push({
          sourceRecordId: `${result.value.municipioId}-${result.value.yearMonth}`,
          payload: result.value,
          fetchedAt,
        });
      } else {
        console.error("RoSepogAdapter: a municipality fetch failed:", result.reason);
      }
    }
    return records;
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const { municipioName, yearMonth, naturezaRows } = record.payload as MunicipioPayload;

    const munMap = await municipioMap();
    const cityIbgeCode = munMap.get(stripAccentsUpper(municipioName));
    if (!cityIbgeCode) return []; // unmatched municipality name — skip rather than guess

    const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");
    const events: SecurityEvent[] = [];

    for (const row of naturezaRows) {
      const naturezaLabel = row[1];
      const count = Number(row[2]);
      if (!naturezaLabel || !Number.isFinite(count) || count <= 0) continue;

      const mapped = NORMALIZED_EVENTO_MAP.get(stripAccentsUpper(naturezaLabel));
      if (!mapped) continue;
      const [eventCategory, eventType] = mapped;

      events.push({
        countryCode: "BR",
        stateCode: "RO",
        cityIbgeCode,
        sourceRecordId: `${cityIbgeCode}-${yearMonth}-${eventType}`,
        sourceType: "official",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        originalCategory: naturezaLabel,
        occurredAt: `${yearMonth}-01T00:00:00-04:00`,
        geoPrecision: "MUNICIPALITY",
        locationConfidence: municipalityLocationConfidence,
        city: municipioName,
        state: "RO",
        occurrenceCount: count,
        severity: severityFor(eventType),
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
      const res = await fetch(`${BASE_URL}/SegurancaPublica`, {
        headers: { "User-Agent": USER_AGENT },
      });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on panel page` };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
