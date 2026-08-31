// BeeAware Brasil roadmap / Phase 8 (second-wave states) — PeAdapter
// (Pernambuco, SDS-PE "Mortes Violentas Intencionais" microdata).
//
// CE (SSPDS/SUPESP) and BA (SSP-BA) were tried first for this wave — both
// are dead ends from this environment: ce.gov.br and its subdomains
// (supesp.ce.gov.br, cearatransparente.ce.gov.br) sit behind an F5
// Distributed Cloud (Volterra) WAF that hard-rejects the request outright
// ("The requested URL was rejected", no JS-challenge cookie to satisfy —
// confirmed live 2026-08-28, every ce.gov.br host tried came back 403 the
// same way regardless of User-Agent/Accept headers), and BA's dados.ba.gov.br
// has the broken TLS certificate chain documented in ba_ssp.ts's own
// header. PE was the next state tried and is genuinely real: sds.pe.gov.br
// is plain Apache with no WAF gate.
//
// AC (Acre) was tried in a later pass (alphabetical sweep of the
// remaining states, 2026-08-30) and is a dead end too, for a third
// distinct reason: SEJUSP-AC's own /estatisticas/ page (sejusp.ac.gov.br)
// links nothing but 11 embedded Power BI reports (app.powerbi.com/view?r=
// ...) — no CSV/XLSX/PDF anywhere on the page. dados.ac.gov.br (the
// state's CKAN open-data portal) has exactly 20 datasets total, all
// generic municipal stats (cattle, HDI, energy consumption, population —
// nothing security-related). Both state police sites are unusable too:
// pc.ac.gov.br is a live WordPress "under maintenance" placeholder, and
// pm.ac.gov.br/pmac.acre.gov.br both refuse the connection outright
// (dead domains). Scraping an app.powerbi.com/view report would mean
// reverse-engineering Power BI's own undocumented internal query API —
// the same category of fragile, ToS-questionable dead end this project
// avoids everywhere else — so AC is left unimplemented rather than
// forcing that.
//
// PB (Paraíba) was tried in the same alphabetical sweep and is a dead
// end for the same class of reason as CE: SEDS-PB's own criminal-
// indicators page (paraiba.pb.gov.br/diretas/secretaria-da-seguranca-e-
// defesa-social/indicadores-criminais) always returns HTTP 200 but sits
// behind F5 Distributed Cloud Bot Defense — every response carries a
// "TS4a345b63..." challenge cookie and serves an obfuscated JS challenge
// plus a CAPTCHA instead of real content, the same vendor family as CE's
// WAF, just a JS-challenge wall instead of an outright 403. No fetch()
// from a plain HTTP client can get past that. Both of PB's open-data
// portals were checked too and carry zero security data: dados.pb.gov.br
// (CKAN) has only 3 organisations registered (cge, sead, sefaz — nothing
// security-related), and the separate CODATA-run API
// (api.dadosabertos.codata.pb.gov.br) has 38 endpoints, all budget/
// revenue/HR/health-administration, none touching crime or occurrences.
//
// PI (Piauí) is a different, unusual kind of dead end: a real public data
// API exists (unlike every case above), it just doesn't work. SSP-PI's
// "Painel de Dados Públicos do DATASSP" (dados.ssp.pi.gov.br) is a
// custom frontend whose JS bundle reveals the real backend at
// metabase.dados.ssp.pi.gov.br — a genuine, live Metabase v0.54.2
// instance with public dashboard sharing enabled (confirmed: 6 public
// dashboard UUIDs found baked into the bundle — CVLI/Roubos e Furtos,
// Crimes contra a mulher, Mortes por Causa Indeterminada — each with a
// real "Tabela detalhada" card that would be exactly the per-occurrence
// data this project wants). But every single query against every single
// card — scalar counts, line charts, tables, across 3 different
// dashboards — returns the same generic
// {"status":"failed","error":"Um erro ocorreu durante o processamento
// desta consulta."} regardless of date-range/filter parameters tried.
// This isn't a client-side parameter problem (confirmed by testing
// several formats and a parameter-free scalar count, all identical
// failures) — it looks like the instance's own database connection is
// broken server-side, nothing fixable from this project's side. PI's
// state-level open-data portals (dados.pi.gov.br, dados.seplan.pi.gov.br)
// are dead ends too: both "Observatório de Dados" category pages
// redirect to an unrelated comunicado.seplan.pi.gov.br landing page.
//
// AM (Amazonas), AP (Amapá) and RN (Rio Grande do Norte) were each tried
// too and are NOT marked as dead ends — every .gov.br host tried for
// each of these 3 states timed out at the TCP level from this
// environment specifically (DNS resolves fine via 8.8.8.8; other states'
// .gov.br hosts, tested back-to-back for comparison, connect normally).
// This looks like a network-level block specific to this sandbox's
// egress rather than anything permanent about these states' own
// infrastructure — worth retrying from a different environment before
// concluding anything.
//
// RO (Rondônia) is a second PI-shaped case: a real, live API exists —
// observatorio.sepog.ro.gov.br's "Painel de Segurança Pública" is a
// custom ASP.NET/DataTables dashboard, and its JS
// (Scripts/site/SegurancaPublicaIndicadores.js) reveals two real POST
// endpoints, /SegurancaPublica/GetDataForTableOcorrenciasIndicadoresPerType
// and /SegurancaPublica/GetDataForChartET, that return well-formed JSON
// ({"result": [...]}). But replaying the exact request shape the page's
// own frontend sends (type=natureza_fato|municipio_fato, tipo=FO_S1,
// periodo_1 as a start/end date pair in the site's own DD/MM/YYYY
// format, empty municipio/natureza filters, the XMLHttpRequest header,
// tried across date ranges from 2019 through the present) always comes
// back {"result":[]} — a valid empty result, not an error, so something
// about the exact parameter contract is still wrong in a way that
// wasn't discoverable from the client-side JS alone. Left unimplemented
// rather than guessing further at an undocumented private API contract.
//
// Source page: https://www.sds.pe.gov.br/estatisticas/indicadores-criminais/
// mortes-violentas-intencionais-mvi — links a single microdata file,
// MICRODADOS_DE_MVI_{start}_A_{end}.xlsx (filename's end-month advances as
// SDS-PE republishes it; MICRODADOS_URL_PATTERN below matches on the
// "MICRODADOS_DE_MVI" prefix rather than hardcoding a month name).
//
// Verified live 2026-08-28 against the real file (4.5MB, downloaded
// directly, no auth/session/WAF gate): a genuine per-victim record, not a
// municipality/month aggregate like RJ-ISP or SSP-BA — 87278 rows spanning
// 2004-01 through 2026-08-12 (most recent row 16 days old at verification
// time), TOTAL DE VITIMAS uniformly 1 (one row = one victim = one event,
// no aggregation logic needed the way SSP-BA's QT_VITIMAS requires).
// Columns confirmed from the real header row: MUNICIPIO, REGIAO_GEOGRAFICA,
// SEXO, NATUREZA JURIDICA, DATA, ANO, IDADE, TOTAL DE VITIMAS. NATUREZA
// JURIDICA is a closed 7-value set (NATUREZA_MAP below is exhaustive for
// what's actually in the file) — every category here is already a
// fatality by this dataset's own scope (Mortes Violentas Intencionais),
// same reasoning as SSP-BA/SEDS-AL: severity is uniformly "high".
//
// The workbook has three sheets — Plan2/Planilha2 are pre-built pivot
// summaries (yearly totals only), Plan1 is the real row-level microdata
// (confirmed via workbook.xml's <sheet> list, not a hardcoded "sheet3.xml"
// guess — see MICRODADOS_SHEET_NAME below, resolved through
// xlsx_lite.ts's resolveSheetEntry the same way ES-SESP does).
//
// No coordinates and no bairro/district column (unlike ES-SESP) — only
// MUNICIPIO, plain text, upper-case, accent-stripped in the source file
// itself (e.g. "SERTAO" — real underlying sharedStrings.xml bytes were
// double-checked to be correctly UTF-8 encoded where accents DO appear,
// e.g. real "SERTÃO"/"REGIÃO" region names; any mojibake seen while
// inspecting this file through a terminal was that terminal's own
// rendering, not a real encoding problem, same caveat ES-SESP's header
// already documents). geoPrecision is therefore MUNICIPALITY, resolved
// via the same accent-insensitive IBGE name match SEDS-AL's adapter uses
// (stripAccentsUpper below is copied verbatim from al_seds.ts rather than
// factored into a shared helper — both files are small and this avoids a
// cross-adapter import for a four-line function). PE has 185 real
// municipalities per IBGE; the file's own distinct MUNICIPIO set is 186 —
// the one extra is "NAO INFORMADO" (9 rows, unmapped city — skipped by
// normalize() rather than guessed, same as AL's `if (!cityIbgeCode)
// continue`). Of the 185 real names, accent-insensitive matching alone
// resolves 180; the other 5 are genuine spelling variants (not accent
// differences) confirmed against IBGE's own list one by one —
// MUNICIPIO_ALIASES below covers all 5, so real coverage is 185/185.
//
// No unique per-row ID in the source (unlike SEDS-AL's ID_CONTROLE) — same
// composite-fingerprint sourceRecordId approach as ES-SESP/SSP-BA
// (municipality + date + category + age, NOT row position — the file is
// republished wholesale every month and a position-based key would mint a
// fresh duplicate for every later row each time an earlier one shifts,
// rather than upserting the same event). Measured against the real file:
// 1256 of 87269 mappable rows (1.4%) share a key with at least one other
// row (same city/day/category/age, genuinely different victims) and so
// collapse into one upserted event — a small, bounded undercount in the
// same spirit as PA-SEGUP's own documented composite-key collision rate,
// not something a per-row index can fix without breaking idempotency
// across monthly re-fetches (see above). dedup-within-batch itself is
// handled generically by ingest-security-sources' runEventAdapter.
//
// DATA is a genuine Excel day-serial (confirmed against the raw sheet
// XML: a plain numeric <c> cell, no t="s" attribute, unlike every
// shared-string column in the same row) — EXCEL_EPOCH_MS/excelSerialToIsoDate
// below is copied from es_sesp.ts's own (verified) conversion rather than
// re-derived.
//
// Whole file (87278 rows, 4.5MB) is small enough to ingest in full each
// run, same reasoning as ES-SESP/SEDS-AL/SSP-BA — no rolling-window
// scoping needed.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import { forEachRow, locateZipEntries, parseSharedStrings, inflateEntrySync, resolveSheetEntry } from "../../xlsx_lite.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const SERIES_PAGE_URL = "https://www.sds.pe.gov.br/estatisticas/indicadores-criminais/mortes-violentas-intencionais-mvi";
const USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
const MICRODADOS_LINK_PATTERN = /href="(\/images\/indicadores\/CVLI\/MICRODADOS_DE_MVI[^"]*\.xlsx)"/i;
const MICRODADOS_SHEET_NAME = "Plan1";
const IBGE_MUNICIPIOS_URL = "https://servicodados.ibge.gov.br/api/v1/localidades/estados/PE/municipios";

// Excel's day-serial epoch is 1899-12-30 — see es_sesp.ts's own comment
// for the off-by-two history; reused verbatim here, verified again
// against this file's real row 2 (serial 37987 -> 2004-01-01, matching
// the ANO=2004 column on the same row).
const EXCEL_EPOCH_MS = Date.UTC(1899, 11, 30);
const MS_PER_DAY = 86_400_000;

function excelSerialToIsoDate(serial: string | undefined): string | undefined {
  const n = Number(serial);
  if (!Number.isFinite(n) || n <= 0) return undefined;
  return new Date(EXCEL_EPOCH_MS + n * MS_PER_DAY).toISOString().slice(0, 10);
}

// NATUREZA JURIDICA -> eventType. Exhaustive: all 7 real values confirmed
// present in the live file (87278/87278 rows matched during verification).
const NATUREZA_MAP: Record<string, string> = {
  "HOMICIDIO": "homicide",
  "FEMINICIDIO": "femicide",
  "INFANTICIDIO": "infanticide",
  "LATROCINIO": "homicide",
  "LESOES CORPORAIS SEGUIDA DE MORTE": "homicide",
  "ESTUPRO DE VULNERAVEL COM RESULTADO MORTE": "sexual_violence",
  "MORTE POR INTERVENCAO LEGAL DE AGENTE DO ESTADO": "police_intervention",
};

function stripAccentsUpper(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().trim();
}

// Accent-insensitive matching alone resolves 180/185 real PE municipality
// names; these 5 are genuine spelling variants in the source file, not
// accent differences — confirmed against IBGE's own list (id, real name):
// 2606903 Iguaracy, 2607604 Ilha de Itamaracá, 2608503 Lagoa de Itaenga,
// 2601607 Belém do São Francisco, 2613107 São Caitano. Keyed on the
// already-stripped source spelling so this sits ahead of the IBGE lookup
// below without changing its accent-insensitive matching logic.
const MUNICIPIO_ALIASES: Record<string, string> = {
  "IGUARACI": "2606903",
  "ITAMARACA": "2607604",
  "LAGOA DO ITAENGA": "2608503",
  "BELEM DE SAO FRANCISCO": "2601607",
  "SAO CAETANO": "2613107",
};

let municipioNameCache: Map<string, string> | undefined;

async function municipioNameMap(): Promise<Map<string, string>> {
  if (municipioNameCache) return municipioNameCache;

  const res = await fetch(IBGE_MUNICIPIOS_URL);
  if (!res.ok) {
    throw new Error(`IBGE PE municipios request failed: ${res.status}`);
  }
  const municipios = (await res.json()) as { id: number; nome: string }[];
  municipioNameCache = new Map(municipios.map((m) => [stripAccentsUpper(m.nome), String(m.id)]));
  return municipioNameCache;
}

function findMicrodadosUrl(html: string): string | undefined {
  const match = MICRODADOS_LINK_PATTERN.exec(html);
  if (!match) return undefined;
  return `https://www.sds.pe.gov.br${match[1]}`;
}

export class PeAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "PE",
      name: "SDS-PE - Mortes Violentas Intencionais (Microdados)",
      organisation: "Secretaria de Defesa Social de Pernambuco",
      sourceType: "official",
      sourceUrl: SERIES_PAGE_URL,
      adapterName: "PeAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const pageRes = await fetch(SERIES_PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!pageRes.ok) {
      throw new Error(`SDS-PE MVI page request failed: ${pageRes.status}`);
    }
    const html = await pageRes.text();
    const fileUrl = findMicrodadosUrl(html);
    if (!fileUrl) return [];

    const fileRes = await fetch(fileUrl, { headers: { "User-Agent": USER_AGENT } });
    if (!fileRes.ok) {
      throw new Error(`SDS-PE microdados file request failed: ${fileRes.status}`);
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

    const sheetEntry = await resolveSheetEntry(bytes, entries, MICRODADOS_SHEET_NAME);
    const sharedStringsEntry = entries.get("xl/sharedStrings.xml");
    if (!sheetEntry || !sharedStringsEntry) return [];

    const sharedStrings = parseSharedStrings(await inflateEntrySync(bytes, sharedStringsEntry));
    const nameMap = await municipioNameMap();

    // Column layout confirmed against the real file's header row (row 1):
    // MUNICIPIO, REGIAO_GEOGRAFICA, SEXO, NATUREZA JURIDICA, DATA, ANO,
    // IDADE, TOTAL DE VITIMAS.
    const COL = { municipio: 0, natureza: 3, data: 4, idade: 6 };

    const events: SecurityEvent[] = [];
    const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");
    let rowIndex = 0;

    await forEachRow(bytes, sheetEntry, sharedStrings, (cells) => {
      rowIndex++;
      if (rowIndex === 1) return; // header row

      const eventType = NATUREZA_MAP[cells[COL.natureza] ?? ""];
      if (!eventType) return; // unmapped natureza — skip rather than guess

      const occurredAt = excelSerialToIsoDate(cells[COL.data]);
      if (!occurredAt) return;

      const municipio = cells[COL.municipio] ?? "";
      const strippedMunicipio = stripAccentsUpper(municipio);
      const cityIbgeCode = MUNICIPIO_ALIASES[strippedMunicipio] ?? nameMap.get(strippedMunicipio);
      if (!cityIbgeCode) return; // "NAO INFORMADO" or an unmatched name

      const idade = cells[COL.idade] ?? "";

      events.push({
        countryCode: "BR",
        stateCode: "PE",
        cityIbgeCode,
        // No unique ID column in the source — same composite-fingerprint
        // approach as ES-SESP/SSP-BA.
        sourceRecordId: `${municipio}|${occurredAt}|${eventType}|${idade}`,
        sourceType: "official",
        eventCategory: "VIOLENCE",
        eventType,
        occurredAt: `${occurredAt}T00:00:00-03:00`,
        geoPrecision: "MUNICIPALITY",
        locationConfidence: municipalityLocationConfidence,
        city: municipio,
        state: "PE",
        occurrenceCount: 1,
        victimCount: 1,
        severity: "high",
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
      const res = await fetch(SERIES_PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on MVI page` };
      }
      const html = await res.text();
      const fileUrl = findMicrodadosUrl(html);
      if (!fileUrl) {
        return { status: "RED", message: "No MICRODADOS_DE_MVI file link found — page markup may have changed" };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
