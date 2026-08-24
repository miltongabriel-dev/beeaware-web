// BeeAware Brasil roadmap / Phase 2 — EsSespAdapter (Espírito Santo,
// SESP Observatório open data).
//
// The best per-occurrence source found in this state-by-state expansion
// so far — better even than PA-SEGUP: https://observatorio.sesp.es.gov.br
// /serie-historica-de-dados lists ~16 static XLSX files, no login/session/
// CSRF dance (unlike PA-SEGUP), no browser-UA gate (unlike SSP-MG). The
// "Homicídios" file (verified live 2026-08-24, ~2.4MB) is real
// per-occurrence data for 1996-2025 with genuine coordinates on every one
// of its 43834 rows (confirmed: 100% coordinate coverage) — precise
// enough for EXACT geoPrecision map pins, not just a municipality
// choropleth. Columns confirmed from the real header: DataObito,
// TipificacaoJuridico, Municipio, Bairro, Rua/Logradouro, REGIÃO,
// IdadeEnvolvido, Genero, CorEnvolvido, Latitude, Longitude.
// TipificacaoJuridico is a closed 2-value set in the real file: "Homicídio
// Doloso" and "Feminicídio".
//
// (A garbled-looking "Homic�dio" first appeared when inspecting this file
// through this session's own terminal/python stdout — verified by reading
// the raw sharedStrings.xml bytes directly that the underlying data is
// correctly UTF-8 encoded (í is the standard 0xC3 0xAD sequence); the
// corruption was this environment's console rendering, not the source
// data. No special decoding needed beyond what xlsx_lite.ts already does.)
//
// DataObito is a genuine Excel date (a numeric day-count cell, styled as
// a date — not a shared string), unlike every other XLSX/CSV adapter in
// this codebase so far; EXCEL_EPOCH_MS below converts it.
//
// Scope: only the Homicídios file for now, not the other ~15 (feminicide
// is already included as a TipificacaoJuridico value within it; several
// of the others — street/commercial/residential robbery — are much
// higher-volume (one robbery file alone: 151998 rows for 2018-2025 vs
// homicide's 43834 for 1996-2025) and lack coordinates (municipality/
// bairro only), a different enough shape (aggregate, not point) to design
// and verify separately rather than rush into this pass.
//
// Uses xlsx_lite.ts (see its own header) — same reasoning as UnodcAdapter,
// though this file is small enough (2.4MB) that SheetJS would likely have
// been fine too; reusing the already-verified reader avoids introducing a
// second XLSX code path for no real benefit.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import { forEachRow, locateZipEntries, parseSharedStrings, inflateEntrySync, resolveSheetEntry } from "../../xlsx_lite.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const SERIES_PAGE_URL = "https://observatorio.sesp.es.gov.br/serie-historica-de-dados";
const USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
const HOMICIDIOS_LINK_PATTERN = /href="(\/Media\/ObservatorioSESP\/SERIE_HISTORICA\/Homic[^"]*\.xlsx)"/i;
const SHEET_NAME = "Planilha2";

// Excel's day-serial epoch is 1899-12-30 (not 1900-01-01 — Excel's own
// well-known off-by-two quirk, inherited from Lotus 1-2-3's fictitious
// 1900 leap day). Confirmed against the real file: serial 46022 in row 2
// matches DataObito 2025-12-31 as read back by openpyxl.
const EXCEL_EPOCH_MS = Date.UTC(1899, 11, 30);
const MS_PER_DAY = 86_400_000;

function excelSerialToIsoDate(serial: string | undefined): string | undefined {
  const n = Number(serial);
  if (!Number.isFinite(n) || n <= 0) return undefined;
  return new Date(EXCEL_EPOCH_MS + n * MS_PER_DAY).toISOString().slice(0, 10);
}

const TIPIFICACAO_MAP: Record<string, string> = {
  "Homicídio Doloso": "homicide",
  "Feminicídio": "femicide",
};

function findHomicidiosUrl(html: string): string | undefined {
  const match = HOMICIDIOS_LINK_PATTERN.exec(html);
  if (!match) return undefined;
  return `https://observatorio.sesp.es.gov.br${match[1].replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)))}`;
}

export class EsSespAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "ES",
      name: "SESP-ES - Observatório de Segurança Pública (Homicídios)",
      organisation: "Secretaria de Estado da Segurança Pública do Espírito Santo",
      sourceType: "official",
      sourceUrl: SERIES_PAGE_URL,
      adapterName: "EsSespAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const pageRes = await fetch(SERIES_PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!pageRes.ok) {
      throw new Error(`SESP-ES series page request failed: ${pageRes.status}`);
    }
    const html = await pageRes.text();
    const fileUrl = findHomicidiosUrl(html);
    if (!fileUrl) return [];

    const fileRes = await fetch(fileUrl, { headers: { "User-Agent": USER_AGENT } });
    if (!fileRes.ok) {
      throw new Error(`SESP-ES Homicídios file request failed: ${fileRes.status}`);
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

    // Column layout confirmed against the real file's header row (row 1):
    // DataObito, TipificacaoJuridico, Municipio, Bairro, Rua/Logradouro,
    // REGIÃO, IdadeEnvolvido, Genero, CorEnvolvido, Latitude, Longitude.
    const COL = {
      data: 0, tipificacao: 1, municipio: 2, bairro: 3, rua: 4,
      idade: 6, genero: 7, latitude: 9, longitude: 10,
    };

    const events: SecurityEvent[] = [];
    const exactLocationConfidence = defaultLocationConfidence("EXACT");
    let rowIndex = 0;

    await forEachRow(bytes, sheetEntry, sharedStrings, (cells) => {
      rowIndex++;
      if (rowIndex === 1) return; // header row

      const eventType = TIPIFICACAO_MAP[cells[COL.tipificacao] ?? ""];
      if (!eventType) return; // unmapped natureza — skip rather than guess

      const occurredAt = excelSerialToIsoDate(cells[COL.data]);
      const latitude = Number(cells[COL.latitude]);
      const longitude = Number(cells[COL.longitude]);
      if (!occurredAt || !Number.isFinite(latitude) || !Number.isFinite(longitude)) return;

      const municipio = cells[COL.municipio] ?? "";
      const bairro = cells[COL.bairro] ?? "";
      const rua = cells[COL.rua] ?? "";
      const idade = cells[COL.idade] ?? "";
      const genero = cells[COL.genero] ?? "";

      events.push({
        countryCode: "BR",
        stateCode: "ES",
        // No unique ID column in the source — same composite-fingerprint
        // approach as PA-SEGUP, dedup already handled generically by
        // runEventAdapter's batch-upsert dedup.
        sourceRecordId: `${municipio}|${occurredAt}|${bairro}|${rua}|${latitude}|${longitude}|${idade}|${genero}`,
        sourceType: "official",
        eventCategory: "VIOLENCE",
        eventType,
        occurredAt: `${occurredAt}T00:00:00-03:00`,
        latitude,
        longitude,
        geoPrecision: "EXACT",
        locationConfidence: exactLocationConfidence,
        neighborhood: bairro || undefined,
        city: municipio || undefined,
        state: "ES",
        occurrenceCount: 1,
        severity: "high",
        confidenceScore: computeConfidenceScore({
          reliabilityGrade: "official_confirmed_record",
          locationConfidence: exactLocationConfidence,
        }),
      });
    });

    return events;
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(SERIES_PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on series page` };
      }
      const html = await res.text();
      const fileUrl = findHomicidiosUrl(html);
      if (!fileUrl) {
        return { status: "RED", message: "No Homicídios file link found — page markup may have changed" };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
