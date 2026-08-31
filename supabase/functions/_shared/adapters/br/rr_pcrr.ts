// BeeAware Brasil roadmap / Phase 8 (alphabetical sweep of the remaining
// states) — RrPcrrAdapter (Roraima, Polícia Civil/NEAC "Mortes Violentas
// Letais Intencionais" microdata, 2019-2025).
//
// policiacivil.rr.gov.br/estatisticas/ publishes 9 real XLSX datasets via
// a WP Download Manager plugin (armas apreendidas, drogas, veículos,
// celulares, estelionato, mandados, violência contra a mulher, and this
// one) — only this one (per-victim MVI microdata) is ingested here, same
// scope-per-state precedent as AlAdapter/MsSejuspAdapter (one core CVLI-
// style dataset, not every dataset a portal happens to expose).
//
// Verified live 2026-08-31:
// https://policiacivil.rr.gov.br/download/?wpdmdl=7321 — a genuine,
// unauthenticated XLSX download (no session/WAF gate). The wpdmdl id is
// a WordPress post id for the "download" attachment; the plugin's own
// convention is to swap the attached file in place on republish rather
// than issue a new id, so — unlike PR's quarterly filename, which
// genuinely changes shape every release — this URL is expected to keep
// working as NEAC's own file gets updated. Confirm this assumption holds
// if healthCheck ever turns RED.
//
// The raw file is NOT what its "Base de Dados" sheet name suggests at
// first glance: `<dimension ref="A1:N1046342">` and 1,046,342 <row>
// elements sound enormous, but all but 1,808 of them are empty,
// self-closing `<row .../>` padding out to Excel's own row ceiling (an
// autoFilter artifact — confirmed via the sheet's own
// `<autoFilter ref="A9:N1809">`). xlsx_lite.ts's forEachRow only matches
// non-self-closing `<row>...</row>` pairs, so the real per-row cost here
// is proportional to the ~1800 populated rows, not the 1M+ nominal
// dimension — no WORKER_RESOURCE_LIMIT concern the way xlsx_lite.ts's own
// header describes for UNODC's much larger real row count.
//
// Row 8 is the header (rows 1-7 are an institutional title block:
// "GOVERNO DE ESTADO DE RORAIMA" / "POLÍCIA CIVIL DE RORAIMA" / "NÚCLEO
// DE ESTATÍSTICA E ANÁLISE CRIMINAL - NEAC" / etc.), row 9 is blank, data
// starts at row 10. Columns confirmed against the real header row: ITEM,
// MÊS, ANO, BAIRRO, DATA DA OCORRÊNCIA (Excel day-serial), MUNICÍPIO,
// NACIONALIDADE, SEXO, IDADE, RAÇA/COR, INSTRUMENTO/MEIO, CARACTERÍSTICAS
// DO INSTRUMENTO, TIPIFICAÇÃO, QUANTIDADE.
//
// TIPIFICAÇÃO is broader than its "MVI" filename implies — NEAC's own
// dataset also carries SUICÍDIO, ACIDENTE DE TRÂNSITO, ACIDENTE DE
// TRABALHO and MORTE A ESCLARECER COM INDÍCIO DE CRIME (an unresolved,
// not-yet-classified death) alongside the real intentional-violence
// types. Only the latter are mapped; the rest are skipped rather than
// guessed, same reasoning as every other adapter here — an accident or
// suicide isn't a violent crime, and an unresolved death might not turn
// out to be one.
//
// ITEM is a plain sequential row index across the WHOLE file (not
// reset per year/month) — used directly as the unique part of
// sourceRecordId, same "use the real row id when the source has one"
// precedent as AlAdapter/MsSejuspAdapter.
//
// Does NOT use xlsx_lite.ts's forEachRow/forEachRowRaw, unlike every
// other XLSX adapter here — found a real pathological-backtracking bug
// in its row regex (/<row[^>]*>(.*?)<\/row>/gs) against this specific
// file's shape. That regex's opening `<row[^>]*>` also matches a
// self-closing `<row .../>` tag in full (the `[^>]*` swallows the
// trailing `/`), so once the lazy `(.*?)</row>` starts scanning forward
// from a self-closing tag with no `</row>` of its own, it keeps
// backtracking through every subsequent self-closing tag looking for the
// next real `</row>` — fine on every other file this reader has seen
// (real rows throughout), catastrophic here because this file's real
// ~1800 rows are followed by ~1,044,500 empty self-closing padding rows
// (an Excel autoFilter artifact — confirmed hanging past 90s in a Node
// timing test against the real file, vs. under 1ms once those padding
// rows are stripped first). Rather than change xlsx_lite.ts's shared
// regex (used by 8 other adapters, untested against this failure mode),
// this file inflates the sheet directly and strips self-closing `<row
// .../>` tags with one linear, non-backtracking pass before applying the
// same buildCellRegex/parseRowCells xlsx_lite.ts already exports — the
// only two exports of the six pulled in here, not forEachRow/
// forEachRowRaw. The sheet decompresses to ~42MB briefly held in memory,
// well inside a single request's budget (a real one-time cost, not a
// per-row one — UNODC's own forEachRow exists to avoid this for a sheet
// with ~126k real rows; this file's real row count is ~1800).

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import { buildCellRegex, inflateEntrySync, locateZipEntries, parseRowCells, parseSharedStrings, resolveSheetEntry } from "../../xlsx_lite.ts";
import type { EventCategory } from "../../taxonomy.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const MVI_XLSX_URL = "https://policiacivil.rr.gov.br/download/?wpdmdl=7321";
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";
const SHEET_NAME = "BASE DE DADOS";
const IBGE_MUNICIPIOS_URL = "https://servicodados.ibge.gov.br/api/v1/localidades/estados/RR/municipios";

// Excel's day-serial epoch — same formula as es_sesp.ts/pe_sds.ts/
// sinesp.ts/sp_vehicle.ts. Verified against this file's real row 10:
// serial 45658 -> 2025-01-01, matching that row's own MÊS=JANEIRO,
// ANO=2025 columns.
const EXCEL_EPOCH_MS = Date.UTC(1899, 11, 30);
const MS_PER_DAY = 86_400_000;

function excelSerialToIsoDate(serial: string | undefined): string | undefined {
  const n = Number(serial);
  if (!Number.isFinite(n) || n <= 0) return undefined;
  return new Date(EXCEL_EPOCH_MS + n * MS_PER_DAY).toISOString().slice(0, 10);
}

// TIPIFICAÇÃO -> [category, eventType]. Not exhaustive by design — see
// file header for the non-crime values (SUICÍDIO, both ACIDENTE types,
// the unresolved "a esclarecer" bucket) deliberately left unmapped.
const TIPIFICACAO_MAP: Record<string, [EventCategory, string]> = {
  "HOMICIDIO": ["VIOLENCE", "homicide"],
  "FEMINICIDIO": ["VIOLENCE", "homicide"],
  "LATROCINIO": ["VIOLENCE", "homicide"],
  "LESAO CORPORAL SEGUIDA DE MORTE": ["VIOLENCE", "homicide"],
  "MORTE POR INTERVENCAO DE AGENTE DO ESTADO": ["VIOLENCE", "police_intervention"],
};

function stripAccentsUpper(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().trim();
}

let municipioNameCache: Map<string, string> | undefined;

async function municipioNameMap(): Promise<Map<string, string>> {
  if (municipioNameCache) return municipioNameCache;

  const res = await fetch(IBGE_MUNICIPIOS_URL);
  if (!res.ok) {
    throw new Error(`IBGE RR municipios request failed: ${res.status}`);
  }
  const municipios = (await res.json()) as { id: number; nome: string }[];
  municipioNameCache = new Map(municipios.map((m) => [stripAccentsUpper(m.nome), String(m.id)]));
  return municipioNameCache;
}

export class RrPcrrAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "RR",
      name: "PC-RR/NEAC - Mortes Violentas Letais Intencionais (Microdados)",
      organisation: "Polícia Civil do Estado de Roraima",
      sourceType: "official",
      sourceUrl: "https://policiacivil.rr.gov.br/estatisticas/",
      adapterName: "RrPcrrAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(MVI_XLSX_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) {
      throw new Error(`PC-RR MVI microdados request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "rr-pcrr-mvi",
        payload: new Uint8Array(await res.arrayBuffer()),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  // See the file header for why this doesn't use xlsx_lite.ts's
  // forEachRow: strips the ~1,044,500 self-closing empty `<row .../>`
  // padding rows in one linear pass first, then runs the same
  // buildCellRegex/parseRowCells xlsx_lite.ts exports over what's left
  // (~1800 real rows) — avoids forEachRowRaw's row regex catastrophically
  // backtracking through that padding.
  private async parseRows(bytes: Uint8Array): Promise<(string | undefined)[][] | undefined> {
    const entries = locateZipEntries(bytes);
    const sheetEntry = await resolveSheetEntry(bytes, entries, SHEET_NAME);
    const sharedStringsEntry = entries.get("xl/sharedStrings.xml");
    if (!sheetEntry || !sharedStringsEntry) return undefined;

    const sharedStrings = parseSharedStrings(await inflateEntrySync(bytes, sharedStringsEntry));
    const sheetXml = await inflateEntrySync(bytes, sheetEntry);
    const withoutPadding = sheetXml.replace(/<row[^>]*\/>/g, "");

    const cellRe = buildCellRegex();
    const rowRe = /<row[^>]*>(.*?)<\/row>/gs;
    const rows: (string | undefined)[][] = [];
    let m: RegExpExecArray | null;
    while ((m = rowRe.exec(withoutPadding))) {
      rows.push(parseRowCells(m[1], cellRe, sharedStrings));
    }
    return rows;
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const bytes = record.payload as Uint8Array;
    const rows = await this.parseRows(bytes);
    if (!rows) return [];

    const nameMap = await municipioNameMap();

    // Column layout confirmed against the real file's header row (row 8):
    // ITEM, MÊS, ANO, BAIRRO, DATA DA OCORRÊNCIA, MUNICÍPIO,
    // NACIONALIDADE, SEXO, IDADE, RAÇA/COR, INSTRUMENTO/MEIO,
    // CARACTERÍSTICAS DO INSTRUMENTO, TIPIFICAÇÃO, QUANTIDADE.
    const COL = { item: 0, bairro: 3, data: 4, municipio: 5, tipificacao: 12, quantidade: 13 };

    const locationConfidence = defaultLocationConfidence("MUNICIPALITY");
    const confidenceScore = computeConfidenceScore({
      reliabilityGrade: "official_confirmed_record",
      locationConfidence,
    });

    const events: SecurityEvent[] = [];

    // rows[0..7]: title block (row 1-8 incl. header), rows[8]: blank
    // spacer (row 9), rows[9+]: real data (row 10+).
    for (let i = 9; i < rows.length; i++) {
      const cells = rows[i];
      const item = cells[COL.item];
      if (!item) continue;

      const mapped = TIPIFICACAO_MAP[stripAccentsUpper(cells[COL.tipificacao] ?? "")];
      if (!mapped) continue; // suicide/accident/unresolved — skip rather than guess
      const [eventCategory, eventType] = mapped;

      const occurredAt = excelSerialToIsoDate(cells[COL.data]);
      if (!occurredAt) continue;

      const municipio = cells[COL.municipio] ?? "";
      const cityIbgeCode = nameMap.get(stripAccentsUpper(municipio));
      if (!cityIbgeCode) continue;

      const bairro = cells[COL.bairro];
      const quantidade = Number(cells[COL.quantidade] ?? "1");
      const victimCount = Number.isFinite(quantidade) && quantidade > 0 ? quantidade : 1;

      events.push({
        countryCode: "BR",
        stateCode: "RR",
        cityIbgeCode,
        sourceRecordId: `RR-mvi-${item}`,
        sourceType: "official",
        eventCategory,
        eventType,
        originalCategory: cells[COL.tipificacao],
        occurredAt: `${occurredAt}T00:00:00-04:00`,
        geoPrecision: "MUNICIPALITY",
        locationConfidence,
        neighborhood: bairro && bairro !== "ZONA RURAL" ? bairro : undefined,
        city: municipio,
        state: "Roraima",
        occurrenceCount: 1,
        victimCount,
        severity: "high",
        confidenceScore,
      });
    }

    return events;
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(MVI_XLSX_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `MVI microdados request failed: ${res.status}` };
      }
      const bytes = new Uint8Array(await res.arrayBuffer());
      const rows = await this.parseRows(bytes);
      if (!rows || rows.length < 10) {
        return { status: "RED", message: `Sheet "${SHEET_NAME}" not found or too short — layout may have changed` };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
