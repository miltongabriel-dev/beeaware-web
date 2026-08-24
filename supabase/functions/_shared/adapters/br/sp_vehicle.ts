// BeeAware Brasil roadmap / Phase 3 — SpVehicleAdapter (São Paulo state,
// SSP-SP "Veículos subtraídos" open data).
//
// Real source, verified live 2026-08-24 — not on the ssp.sp.gov.br/
// estatistica/consultas page itself (a client-rendered Angular SPA that
// returns nothing to a plain fetch); the actual files are listed in a
// small JSON manifest the SPA fetches at runtime:
// https://www.ssp.sp.gov.br/assets/estatistica/transparencia/
// baseDadosCelVeiEObjSub.json — one section per theft category
// ("Celulares subtraídos", "Veículos subtraídos", "Objetos subtraídos"),
// each a { periodo, arquivo }[] list of yearly XLSX files back to 2017.
// No login, no browser-UA gate (unlike SSP-MG), no broken TLS chain
// (unlike SSP-BA) — a plain unauthenticated static download, confirmed
// via `openssl s_client` and a bare `curl` with no User-Agent.
//
// Real per-occurrence data, genuinely large: the current (partial) year
// alone is ~30MB compressed / ~203MB of raw sheet XML for ~104k rows —
// over 3x the biggest file xlsx_lite.ts had been proven against
// (UNODC's 61.5MB). Uses xlsx_lite.ts for the same reason as ES-SESP —
// its streaming reader never holds more than one decompressed chunk in
// memory regardless of total sheet size, so this is a scale test of an
// already-proven approach rather than a new one.
//
// This is NOT a "stolen vehicles" table on its own — it's every BO
// (police report) that references a vehicle, including recovery/delivery
// records ("Localização/Apreensão de veículo"), plate-tampering charges,
// receiving-stolen-goods, and unrelated crimes that merely happened to
// involve a vehicle (DUI, drug trafficking, homicide, collisions...).
// Real distinct RUBRICA (legal classification) values in the live file:
// 144, only 2 of which are the actual theft/robbery event this adapter
// is scoped to — RUBRICA_MAP below is a deliberate narrow allowlist
// (skip rather than guess), not an exhaustive map of all 144 like
// SSP-MG/SSP-BA's natureza tables.
//
// Real column layout confirmed against the live file's header row (55
// columns, A-BC) — richer than every other Brazilian adapter so far:
// genuine LATITUDE/LONGITUDE (AN/AO), a real 7-digit IBGE code with no
// check-digit stripping needed (COD IBGE, BC — unlike SSP-MG/SSP-BA's
// 6-digit prefix match), and a real per-row control number (CONT_VEICULO)
// usable directly as sourceRecordId, same "real ID win" as SEDS-AL's
// ID_CONTROLE. PLACA_VEICULO (plate) exists in the source but is
// deliberately NOT read into the normalized event — LGPD minimisation
// (roadmap §10.1: no identifiable licence plates in the public layer).
//
// The data sheet's own name is year-specific ("VEICULOS_2026",
// presumably "VEICULOS_2025" etc. in older files) — resolved by
// excluding the two known fixed metadata sheet names ("METODOLOGIA",
// "DICIONARIO DE DADOS") rather than assuming a name, so this doesn't
// silently break on the next year's file.
//
// Scope: only the single most recent year-month present in the fetched
// file, same reasoning as RS-SSP — the source can't be range-fetched by
// date (one static file per calendar year), but nothing requires writing
// every historical row on every run.
//
// IMPORTANT — the real bottleneck here, found via instrumented timing
// runs against production (not guessed): this adapter's
// WORKER_RESOURCE_LIMIT crashes are NOT about parsing cost. Three
// different normalize() strategies (full object-building, a cheap
// scan-first pass, and the buffered-tail approach below) all failed at
// a similar ~11-12.5s — the tell that parsing logic wasn't the variable.
// A performance.now()-instrumented run that returned cleanly (rather
// than crashing) confirmed why: zip-setup + sharedStrings parsing is
// genuinely fast (85ms) — the time is spent in fetch() itself, and it is
// NOT a stable slow rate. Across several real attempts: one full request
// (setup-only) completed in 13s total; full-pipeline attempts failed at
// 10.9s and 12.5s; one attempt didn't even fail — it hung past 100s with
// no response at all. `curl` from outside Supabase measured this same
// file downloading at a consistent ~250KB/s (100+ seconds for 30MB), so
// dados.ssp.sp.gov.br is a genuinely slow/unreliable server — the
// question is only whether a given attempt's connection happens to be
// fast enough to finish before something (the platform's own timeout, or
// the slow transfer itself) cuts it off. This is a real external
// constraint, the same class of problem as SSP-BA's broken TLS chain
// (ba_ssp.ts) — a slow/unreliable origin server, not slow client-side
// code. No fetch-side optimization in this codebase can make a
// government file server serve bytes faster or more consistently.
//
// The buffered-tail parsing below (xlsx_lite.ts's forEachRowRaw, only
// running the expensive full 55-column parseRowCells on the most recent
// ~25k of ~104k rows, found via confirming the file is chronologically
// ordered by registration month ascending) is kept anyway — it's a real
// efficiency win for whenever this file *does* finish downloading, and
// this source's unusually wide 55-column rows make it broadly useful,
// but it was not what turned out to be broken here.
//
// NOT REGISTERED in index.ts's eventAdapters — unlike RS-SSP's ~12.5%
// nonzero real-mode success rate (where a retry cadence is a legitimate
// mitigation), every full-pipeline attempt against this source has
// failed outright (crash or hang, never a completion), so a cron retry
// cadence has no confirmed chance of ever succeeding as currently
// architected. Worth revisiting with a genuinely chunked/multi-invocation
// download (the same "bigger lift" flagged in rs_ssp.ts's own header) —
// e.g. persisting partial downloaded bytes across invocations via
// Storage, or moving the fetch outside the Edge Function's own execution
// window entirely — before concluding it's unfixable. The adapter logic
// itself is otherwise correct and ready to register the moment fetch()
// can reliably pull this file within one invocation's time budget.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import {
  forEachRowRaw,
  parseRowCells,
  buildCellRegex,
  locateZipEntries,
  parseSharedStrings,
  inflateEntrySync,
  type ZipEntry,
} from "../../xlsx_lite.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const MANIFEST_URL = "https://www.ssp.sp.gov.br/assets/estatistica/transparencia/baseDadosCelVeiEObjSub.json";
const SECTION_NAME = "Veículos subtraídos";
const NON_DATA_SHEET_NAMES = new Set(["METODOLOGIA", "DICIONARIO DE DADOS"]);

interface ManifestFile {
  periodo: string;
  arquivo: string;
}
interface ManifestSection {
  nome: string;
  lista: ManifestFile[];
}
interface ManifestResponse {
  data: ManifestSection[];
}

async function findLatestFileUrl(): Promise<string | undefined> {
  const res = await fetch(MANIFEST_URL);
  if (!res.ok) {
    throw new Error(`SSP-SP manifest request failed: ${res.status}`);
  }
  const manifest = (await res.json()) as ManifestResponse;
  const section = manifest.data.find((s) => s.nome === SECTION_NAME);
  if (!section || section.lista.length === 0) return undefined;

  const latest = [...section.lista].sort((a, b) => Number(b.periodo) - Number(a.periodo))[0];
  return `https://www.ssp.sp.gov.br/${latest.arquivo}`;
}

// Same resolveSheetEntry logic xlsx_lite.ts exports, but by exclusion
// rather than an exact name match — this workbook's data sheet is named
// after the year it covers ("VEICULOS_2026"), not a fixed string.
async function resolveDataSheetEntry(
  bytes: Uint8Array,
  entries: Map<string, ZipEntry>,
): Promise<ZipEntry | undefined> {
  const workbookEntry = entries.get("xl/workbook.xml");
  const relsEntry = entries.get("xl/_rels/workbook.xml.rels");
  if (!workbookEntry || !relsEntry) return undefined;

  const workbookXml = await inflateEntrySync(bytes, workbookEntry);
  const sheetMatch = [...workbookXml.matchAll(/<sheet name="([^"]+)"[^>]*r:id="(rId\d+)"/g)]
    .find(([, name]) => !NON_DATA_SHEET_NAMES.has(name));
  if (!sheetMatch) return undefined;
  const rId = sheetMatch[2];

  const relsXml = await inflateEntrySync(bytes, relsEntry);
  const relMatch = new RegExp(`<Relationship Id="${rId}"[^>]*Target="([^"]+)"`).exec(relsXml);
  if (!relMatch) return undefined;

  return entries.get(`xl/${relMatch[1]}`);
}

// RUBRICA -> eventType. Deliberately narrow: 2 of the file's 144 real
// distinct values. Everything else (recovery/delivery records, plate
// tampering, receiving stolen goods, unrelated crimes that merely
// involved a vehicle) is skipped, not guessed.
const RUBRICA_MAP: Record<string, string> = {
  "Furto (art. 155)": "vehicle_theft",
  "Roubo (art. 157)": "vehicle_robbery",
};

// Excel's day-serial epoch — same as EsSespAdapter (EXCEL_EPOCH_MS
// header there explains the 1899-12-30 off-by-two quirk).
const EXCEL_EPOCH_MS = Date.UTC(1899, 11, 30);
const MS_PER_DAY = 86_400_000;

function excelSerialToIsoDate(serial: string | undefined): string | undefined {
  const n = Number(serial);
  if (!Number.isFinite(n) || n <= 0) return undefined;
  return new Date(EXCEL_EPOCH_MS + n * MS_PER_DAY).toISOString().slice(0, 10);
}

// HORA_OCORRENCIA is a fractional day (0.40972... = 09:50:00), a separate
// cell from the date — combined here into a real occurredAt time-of-day
// rather than defaulting to midnight the way ES-SESP does (that source
// has no separate time cell to combine).
function excelFractionToTime(fraction: string | undefined): string {
  const f = Number(fraction);
  if (!Number.isFinite(f) || f < 0 || f >= 1) return "00:00:00";
  const totalSeconds = Math.round(f * 86400);
  const hh = String(Math.floor(totalSeconds / 3600)).padStart(2, "0");
  const mm = String(Math.floor((totalSeconds % 3600) / 60)).padStart(2, "0");
  const ss = String(totalSeconds % 60).padStart(2, "0");
  return `${hh}:${mm}:${ss}`;
}

const LOW_SEVERITY = new Set(["vehicle_theft"]);
function severityFor(eventType: string): string {
  // Roubo (robbery) involves a threat or violence by definition; furto
  // (theft) does not — same low/medium split PA-SEGUP uses for its own
  // theft-vs-other property crimes.
  return LOW_SEVERITY.has(eventType) ? "low" : "medium";
}

export class SpVehicleAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "SP",
      name: "SSP-SP - Veículos Subtraídos",
      organisation: "Secretaria de Segurança Pública do Estado de São Paulo",
      sourceType: "official",
      sourceUrl: "https://www.ssp.sp.gov.br/estatistica/consultas",
      adapterName: "SpVehicleAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const fileUrl = await findLatestFileUrl();
    if (!fileUrl) return [];

    const fileRes = await fetch(fileUrl);
    if (!fileRes.ok) {
      throw new Error(`SSP-SP vehicle-theft file request failed: ${fileRes.status}`);
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

    const sheetEntry = await resolveDataSheetEntry(bytes, entries);
    const sharedStringsEntry = entries.get("xl/sharedStrings.xml");
    if (!sheetEntry || !sharedStringsEntry) return [];

    const sharedStrings = parseSharedStrings(await inflateEntrySync(bytes, sharedStringsEntry));

    // Column layout confirmed against the real file's header row (row 1,
    // A-BC): ID_DELEGACIA..NOME_MUNICIPIO_CIRC (jurisdiction fields, not
    // used), DATA_OCORRENCIA_BO/HORA_OCORRENCIA (occurrence date/time),
    // RUBRICA (legal classification), CIDADE/BAIRRO (the actual
    // occurrence location, distinct from the jurisdiction fields —
    // LOGRADOURO/street address exists in the source too but SecurityEvent
    // has no street field to put it in, same as ES-SESP), LATITUDE/
    // LONGITUDE, vehicle descriptors, MES_REGISTRO_BO/ANO_REGISTRO_BO
    // (used only for the recent-month scope below), and COD IBGE (a real
    // 7-digit code, no prefix-matching needed).
    const COL = {
      dataOcorrencia: 12, horaOcorrencia: 13, rubrica: 26,
      cidade: 32, bairro: 33,
      latitude: 39, longitude: 40, contVeiculo: 41,
      tipoVeiculo: 43,
      mesRegistro: 49, anoRegistro: 50,
      codIbge: 54,
    };

    // Real column indices for the two plain-numeric cells (no t="s") we
    // need to inspect on every row during the cheap streaming pass, ahead
    // of the real per-cell parse — matches COL.mesRegistro/anoRegistro
    // above, kept as raw column letters here since this regex runs
    // directly against unparsed row XML.
    const MES_REGISTRO_LETTER = "AX";
    const ANO_REGISTRO_LETTER = "AY";
    const plainCellRe = (letter: string) => new RegExp(`<c r="${letter}\\d+"[^>]*><v>(.*?)</v></c>`);
    const mesRe = plainCellRe(MES_REGISTRO_LETTER);
    const anoRe = plainCellRe(ANO_REGISTRO_LETTER);

    // The file is chronologically ordered by registration month ascending
    // (confirmed locally against the real file), so the most recent
    // month's rows are always the tail — buffering the last ~25k raw rows
    // is a generous margin over the ~15-20k rows/month seen in the real
    // file. Only row-boundary splitting (forEachRowRaw) plus two tiny
    // single-column regexes run per row during the full streaming pass;
    // the expensive full 55-column parse (parseRowCells) only ever runs
    // on this small buffered tail afterwards, not on all ~104k rows.
    const RECENT_ROW_BUFFER = 25_000;
    let buffer: string[] = [];
    let rawRowIndex = 0;

    await forEachRowRaw(bytes, sheetEntry, (rowInnerXml) => {
      rawRowIndex++;
      if (rawRowIndex === 1) return; // header row

      const mes = mesRe.exec(rowInnerXml)?.[1];
      const ano = anoRe.exec(rowInnerXml)?.[1];
      if (!mes || !ano) return; // no registration month — can't be scoped, skip

      buffer.push(rowInnerXml);
      if (buffer.length > RECENT_ROW_BUFFER * 2) {
        buffer = buffer.slice(-RECENT_ROW_BUFFER);
      }
    });
    if (buffer.length === 0) return [];
    if (buffer.length > RECENT_ROW_BUFFER) buffer = buffer.slice(-RECENT_ROW_BUFFER);

    const cellRe = buildCellRegex();
    const parsedBuffer = buffer.map((rowInnerXml) => parseRowCells(rowInnerXml, cellRe, sharedStrings));

    let latestYearMonth: string | undefined;
    for (const cells of parsedBuffer) {
      const mes = cells[COL.mesRegistro]?.padStart(2, "0");
      const ano = cells[COL.anoRegistro];
      if (!mes || !ano) continue;
      const yearMonth = `${ano}-${mes}`;
      if (!latestYearMonth || yearMonth > latestYearMonth) latestYearMonth = yearMonth;
    }
    if (!latestYearMonth) return [];

    const events: SecurityEvent[] = [];
    const exactLocationConfidence = defaultLocationConfidence("EXACT");

    for (const cells of parsedBuffer) {
      const mes = cells[COL.mesRegistro]?.padStart(2, "0");
      const ano = cells[COL.anoRegistro];
      if (!mes || !ano || `${ano}-${mes}` !== latestYearMonth) continue;

      const eventType = RUBRICA_MAP[cells[COL.rubrica] ?? ""];
      if (!eventType) continue; // unmapped rubrica — not a vehicle theft/robbery event

      const contVeiculo = cells[COL.contVeiculo];
      if (!contVeiculo) continue;

      const occurredDate = excelSerialToIsoDate(cells[COL.dataOcorrencia]);
      const cityIbgeCode = cells[COL.codIbge];
      const latitude = Number(cells[COL.latitude]);
      const longitude = Number(cells[COL.longitude]);
      if (!occurredDate || !cityIbgeCode || !Number.isFinite(latitude) || !Number.isFinite(longitude)) continue;

      const time = excelFractionToTime(cells[COL.horaOcorrencia]);
      const bairro = cells[COL.bairro];
      const cidade = cells[COL.cidade];
      const rubrica = cells[COL.rubrica];
      const tipoVeiculo = cells[COL.tipoVeiculo];

      events.push({
        countryCode: "BR",
        stateCode: "SP",
        cityIbgeCode,
        sourceRecordId: contVeiculo,
        sourceType: "official",
        eventCategory: "PROPERTY",
        eventType,
        eventSubtype: tipoVeiculo && tipoVeiculo !== "NULL" ? tipoVeiculo : undefined,
        originalCategory: rubrica,
        occurredAt: `${occurredDate}T${time}-03:00`,
        latitude,
        longitude,
        geoPrecision: "EXACT",
        locationConfidence: exactLocationConfidence,
        neighborhood: bairro && bairro !== "NULL" ? bairro : undefined,
        city: cidade,
        state: "SP",
        occurrenceCount: 1,
        severity: severityFor(eventType),
        confidenceScore: computeConfidenceScore({
          reliabilityGrade: "official_confirmed_record",
          locationConfidence: exactLocationConfidence,
        }),
      });
    }

    return events;
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const fileUrl = await findLatestFileUrl();
      if (!fileUrl) {
        return { status: "RED", message: "No 'Veículos subtraídos' section found in SSP-SP manifest" };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
