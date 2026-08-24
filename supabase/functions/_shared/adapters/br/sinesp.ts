// BeeAware Brasil roadmap — SINESP adapter (section 3.1, Phase 1).
//
// Full trail from a broken adapter to a working one:
//   - dados.gov.br's REST API (metadata) works with the
//     `chave-api-dados-abertos` header, but every resource it lists
//     points at dados.mj.gov.br — a domain that no longer resolves at
//     all (DNS failure, re-verified live 2026-08-24). A guessed
//     undocumented download-by-resource-id path on dados.gov.br itself
//     also 200s, but with the SPA's own HTML shell, not real data — a
//     dead end, not a working alternative (re-verified live, same date).
//   - The REAL working path was found via web search, not the CKAN/REST
//     API at all: gov.br hosts the same "Base de Dados VDE" files
//     directly on its own domain, one XLSX per year, at
//     https://www.gov.br/mj/pt-br/assuntos/sua-seguranca/seguranca-publica/
//     estatistica/download/dnsp-base-de-dados/bancovde-{year}.xlsx/@@download/file
//     — confirmed live: HEAD requests 403 (a WAF quirk — GET works fine
//     with a browser User-Agent, same class of gate as SSP-MG), and a
//     real GET returns a genuine XLSX (PK zip signature, valid workbook
//     structure). This is BeeAware's actual national SINESP source, not
//     the CKAN metadata API — sourceUrl below points to the human-
//     readable page that links these files, not the (now-unused)
//     dados.gov.br API base.
//
// Real per-row scale: bancovde-2026.xlsx (current year, verified live) is
// 19.6MB compressed / ~255MB of raw sheet XML, dimension A1:N485176 —
// 485175 data rows. No sharedStrings.xml at all — every cell is either a
// plain number/date serial or an inline string (t="inlineStr",
// <is><t>...</t></is>), which xlsx_lite.ts didn't support before this
// adapter (see its own header/buildCellRegex for the extension).
//
// This is a dense municipality × month × event-type cross-product, NOT
// per-occurrence data — most rows are genuinely all-zero (e.g. no
// feminicídio in a given small municipality that month), matching the
// roadmap's own framing (3.1: "not a source of exact incident pins").
// Real columns confirmed from the header row: uf, municipio, evento,
// data_referencia (Excel day-serial, first-of-month), agente, arma,
// faixa_etaria, feminino, masculino, nao_informado, total_vitima, total,
// total_peso, abrangencia.
//
// `abrangencia` is not a geographic-scope field (every row already has a
// real municipality) — it names which police force reported the row:
// "Estadual" (402434 rows, civil/military state police — SINESP's core
// mandate), "Polícia Federal" (43107 rows, federal-jurisdiction crimes),
// "Polícia Rodoviária Federal" (39733 rows). That last one is literally
// PRF's own data — this project already has PrfAccidentsAdapter (real
// per-occurrence coordinates, prf.ts), so including it here would
// duplicate/conflate a coarser aggregate of the same source under a
// different adapter. Scoped to "Estadual" only for this pass — "Polícia
// Federal" is a real, non-overlapping scope this adapter could add later,
// deliberately deferred rather than guessed at without dedicated review.
//
// `evento` has 31 real distinct values (confirmed against the live
// file) — EVENTO_MAP below is a deliberate allowlist, not exhaustive:
// administrative/service stats (arrest warrants served, inspections,
// license issuance, ambulance/rescue/firefighting dispatch counts other
// than "Combate a incêndios" itself) and sensitive categories with no
// safe generic bucket (suicide, missing persons, agent/officer deaths
// with unclear cause) are deliberately skipped rather than force-fit.
//
// Municipality identity: the source gives uf + municipio (free text,
// original diacritics dropped by whatever exported this file — Google's
// mojibake on "UIBAÍ" etc. Was double-checked to be a genuine encoding
// loss upstream, not a rendering artifact like the false alarms this
// project hit with ES/FCDO — confirmed by testing an accent-insensitive
// match against IBGE's real names, which is what accent-insensitive
// matching is for regardless of which side lost the accents), no IBGE
// code — resolved via IBGE's national municipios endpoint (every
// municipality in Brazil in one call, keyed by (uf, accent-stripped
// name) since municipality names collide across states), same
// accent-insensitive technique RS-SSP/SEDS-AL use, generalised to
// national scope since this adapter (unlike any single-state adapter)
// covers all 27 UFs in one file.
//
// Scope: most recent 3 months by data_referencia — this is national
// aggregate data across ~5300 municipalities and up to 20 mapped event
// types; even after abrangencia/evento/zero-count filtering, a full
// year is far more than the map/baseline use case (roadmap 1.2's
// "Recent Activity" dimension) needs on every run.
//
// NOT REGISTERED in index.ts's eventAdapters — the adapter logic is
// correct (parsing verified against the real file's actual structure
// locally: inline strings, column layout, evento/abrangencia value
// sets, municipality-name matching), but fetch() has failed 3/3 real
// attempts in production, each dying inside fetch() itself (confirmed —
// a version that returned immediately after fetch(), before touching
// the sheet, still failed at the same ~43-46s) at a consistent time
// unlike SP-Vehicle's high-variance failures. The likely cause: this
// Supabase project runs in West Europe (London) — every fetch to a
// Brazilian government server crosses the Atlantic, and this project now
// has two large Brazilian sources (this one, ~20MB; SpVehicleAdapter,
// ~30MB) both failing to complete a single-invocation download, plus
// RsSspAdapter (already known flaky before this session, ~9-123MB)
// showing the same shape of problem at a smaller scale. Every source
// under ~3MB in this project (ES-SESP, SEDS-AL) has always worked
// cleanly. That's circumstantial, not proven, but consistent enough
// across three independent sources to treat as a real infrastructure
// constraint — worth raising with the user directly (region migration,
// or a chunked/multi-invocation download architecture) rather than
// re-diagnosing per-adapter again. Ready to register the moment fetch()
// can reliably complete within one invocation's time budget.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import { forEachRowRaw, parseRowCells, buildCellRegex, locateZipEntries } from "../../xlsx_lite.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const SOURCE_PAGE_URL =
  "https://www.gov.br/mj/pt-br/assuntos/sua-seguranca/seguranca-publica/estatistica/dados-nacionais-1/base-de-dados-e-notas-metodologicas-dos-gestores-estaduais-sinesp-vde-2022-e-2023";
const USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
const IBGE_MUNICIPIOS_URL = "https://servicodados.ibge.gov.br/api/v1/localidades/municipios";

function bancovdeUrl(year: number): string {
  return `https://www.gov.br/mj/pt-br/assuntos/sua-seguranca/seguranca-publica/estatistica/download/dnsp-base-de-dados/bancovde-${year}.xlsx/@@download/file`;
}

// evento -> eventType. Deliberate allowlist (20 of 31 real distinct
// values) — administrative/service stats and sensitive
// no-safe-generic-bucket categories are skipped, not guessed. femicide
// and attempted_femicide follow the precedent EsSespAdapter/AlAdapter/
// BaAdapter already set for using event_type values not literally listed
// in taxonomy.ts's array (that array is descriptive, not a strict enum —
// see taxonomy.ts's own header comment).
const EVENTO_MAP: Record<string, [category: string, type: string]> = {
  "Mortes no trânsito": ["ROAD_SAFETY", "fatal_accident"],
  "Morte no trânsito ou em decorrência dele (exceto homicídio doloso)": ["ROAD_SAFETY", "fatal_accident"],
  "Roubo seguido de morte (latrocínio)": ["VIOLENCE", "homicide"],
  "Homicídio doloso": ["VIOLENCE", "homicide"],
  "Tentativa de homicídio": ["VIOLENCE", "attempted_homicide"],
  "Tentativa de feminicídio": ["VIOLENCE", "attempted_femicide"],
  "Lesão corporal seguida de morte": ["VIOLENCE", "homicide"],
  "Feminicídio": ["VIOLENCE", "femicide"],
  "Morte por intervenção de Agente do Estado": ["VIOLENCE", "police_intervention"],
  "Estupro": ["VIOLENCE", "sexual_violence"],
  "Estupro de vulnerável": ["VIOLENCE", "sexual_violence"],
  "Arma de Fogo Apreendida": ["PUBLIC_SAFETY", "weapon"],
  "Apreensão de Cocaína": ["PUBLIC_SAFETY", "drugs"],
  "Apreensão de Maconha": ["PUBLIC_SAFETY", "drugs"],
  "Tráfico de drogas": ["PUBLIC_SAFETY", "drugs"],
  "Combate a incêndios": ["PUBLIC_SAFETY", "fire"],
  "Furto de veículo": ["PROPERTY", "vehicle_theft"],
  "Roubo de veículo": ["PROPERTY", "vehicle_robbery"],
  "Roubo de carga": ["PROPERTY", "cargo_robbery"],
  "Roubo a instituição financeira": ["PROPERTY", "robbery"],
};

function stripAccentsUpper(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().trim();
}

const NORMALIZED_EVENTO_MAP = new Map(
  Object.entries(EVENTO_MAP).map(([k, v]) => [stripAccentsUpper(k), v]),
);

const EXCEL_EPOCH_MS = Date.UTC(1899, 11, 30);
const MS_PER_DAY = 86_400_000;

function excelSerialToIsoDate(serial: string | undefined): string | undefined {
  const n = Number(serial);
  if (!Number.isFinite(n) || n <= 0) return undefined;
  return new Date(EXCEL_EPOCH_MS + n * MS_PER_DAY).toISOString().slice(0, 10);
}

const HIGH_SEVERITY = new Set([
  "homicide",
  "femicide",
  "attempted_homicide",
  "attempted_femicide",
  "sexual_violence",
  "police_intervention",
]);
const LOW_SEVERITY = new Set(["vehicle_theft"]);
function severityFor(eventType: string): string {
  if (HIGH_SEVERITY.has(eventType)) return "high";
  if (LOW_SEVERITY.has(eventType)) return "low";
  return "medium";
}

interface IbgeMunicipio {
  id: number;
  nome: string;
  microrregiao?: { mesorregiao?: { UF?: { sigla?: string } } };
  "regiao-imediata"?: { "regiao-intermediaria"?: { UF?: { sigla?: string } } };
}

let municipioMapCache: Map<string, string> | undefined;

// National lookup (every Brazilian municipality in one call) rather than
// one call per UF — this adapter (unlike any single-state adapter in
// this project) covers all 27 UFs from a single source file, so a
// per-state fetch loop would just be 27 calls to build the same map.
// IBGE's nested locality shape changed across API versions (both a
// microrregiao->mesorregiao->UF path and a regiao-imediata->
// regiao-intermediaria->UF path exist in real responses depending on
// when a municipality's record was last touched) — read whichever is
// present rather than assuming one.
async function municipioMap(): Promise<Map<string, string>> {
  if (municipioMapCache) return municipioMapCache;

  const res = await fetch(IBGE_MUNICIPIOS_URL);
  if (!res.ok) {
    throw new Error(`IBGE national municipios request failed: ${res.status}`);
  }
  const municipios = (await res.json()) as IbgeMunicipio[];

  const map = new Map<string, string>();
  for (const m of municipios) {
    const uf = m.microrregiao?.mesorregiao?.UF?.sigla ??
      m["regiao-imediata"]?.["regiao-intermediaria"]?.UF?.sigla;
    if (!uf) continue;
    map.set(`${uf}|${stripAccentsUpper(m.nome)}`, String(m.id));
  }
  municipioMapCache = map;
  return map;
}

export class SinespAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      name: "SINESP VDE - Base de Dados Nacional",
      organisation: "Ministério da Justiça e Segurança Pública",
      sourceType: "official",
      sourceUrl: SOURCE_PAGE_URL,
      adapterName: "SinespAdapter",
      adapterVersion: "1.0.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const year = new Date().getUTCFullYear();
    const url = bancovdeUrl(year);
    const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) {
      throw new Error(`SINESP bancovde-${year}.xlsx request failed: ${res.status}`);
    }
    const bytes = new Uint8Array(await res.arrayBuffer());

    return [
      {
        sourceRecordId: `bancovde-${year}`,
        payload: { bytes },
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const { bytes } = record.payload as { bytes: Uint8Array };

    const entries = locateZipEntries(bytes);
    const sheetEntry = entries.get("xl/worksheets/sheet1.xml");
    if (!sheetEntry) return [];

    const munMap = await municipioMap();
    const cellRe = buildCellRegex();

    // Column layout confirmed against the real file's header row (row 1,
    // A-N): uf, municipio, evento, data_referencia, agente, arma,
    // faixa_etaria, feminino, masculino, nao_informado, total_vitima,
    // total, total_peso, abrangencia. No sharedStrings.xml in this file
    // (every string cell is inline) — pass an empty array, parseRowCells
    // only consults it for t="s" cells, which don't exist here.
    const COL = {
      uf: 0, municipio: 1, evento: 2, dataReferencia: 3,
      totalVitima: 10, total: 11, abrangencia: 13,
    };

    const now = new Date();
    const recentYearMonths = new Set<string>();
    for (let i = 0; i < 3; i++) {
      const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1));
      recentYearMonths.add(`${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`);
    }

    const events: SecurityEvent[] = [];
    const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");
    let rowIndex = 0;

    await forEachRowRaw(bytes, sheetEntry, (rowInnerXml) => {
      rowIndex++;
      if (rowIndex === 1) return; // header row

      const cells = parseRowCells(rowInnerXml, cellRe, []);

      if (cells[COL.abrangencia] !== "Estadual") return; // federal/PRF scope excluded — see file header

      const mapped = NORMALIZED_EVENTO_MAP.get(stripAccentsUpper(cells[COL.evento] ?? ""));
      if (!mapped) return; // unmapped evento — administrative/sensitive, skip rather than guess
      const [eventCategory, eventType] = mapped;

      const occurredDate = excelSerialToIsoDate(cells[COL.dataReferencia]);
      if (!occurredDate) return;
      const yearMonth = occurredDate.slice(0, 7);
      if (!recentYearMonths.has(yearMonth)) return;

      const total = Number(cells[COL.total]);
      const totalVitima = Number(cells[COL.totalVitima]);
      const occurrenceCount = Number.isFinite(total) && total > 0
        ? total
        : (Number.isFinite(totalVitima) && totalVitima > 0 ? totalVitima : 0);
      if (occurrenceCount <= 0) return; // dense cross-product — most rows are genuinely zero

      const uf = cells[COL.uf];
      const municipio = cells[COL.municipio];
      if (!uf || !municipio) return;

      const cityIbgeCode = munMap.get(`${uf}|${stripAccentsUpper(municipio)}`);
      if (!cityIbgeCode) return; // unmatched municipality name — skip rather than guess

      events.push({
        countryCode: "BR",
        stateCode: uf,
        cityIbgeCode,
        sourceRecordId: `${cityIbgeCode}-${yearMonth}-${eventType}`,
        sourceType: "official",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        originalCategory: cells[COL.evento],
        occurredAt: `${occurredDate}T00:00:00-03:00`,
        geoPrecision: "MUNICIPALITY",
        locationConfidence: municipalityLocationConfidence,
        city: municipio,
        state: uf,
        occurrenceCount,
        victimCount: Number.isFinite(totalVitima) ? totalVitima : undefined,
        severity: severityFor(eventType),
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
      // Checks the source page, not the file itself — a real GET on
      // bancovde-{year}.xlsx works (confirmed live) but downloads the
      // whole ~20MB file, and healthCheck() runs before fetch() on every
      // invocation (runEventAdapter's own order); doubling the download
      // just to report health would waste real budget on a source
      // that's already large. HEAD 403s on this source (a WAF quirk) so
      // isn't usable here either — the source page itself has no such
      // gate.
      const res = await fetch(SOURCE_PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on source page` };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
