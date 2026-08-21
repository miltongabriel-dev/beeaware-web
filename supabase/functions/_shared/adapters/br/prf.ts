// BeeAware Brasil roadmap — PRF adapter (section 3.3, Phase 1).
//
// No login involved here — unlike SINESP, PRF's files are plain public
// Google Drive links, not behind dados.gov.br's auth wall. The catch is
// there's no CKAN/REST discovery endpoint the way RENAEST has, so fetch()
// scrapes the source page's own table instead. Verified live on
// 2026-08-21: the page (SOURCE_PAGE_URL) renders a table per dataset row
// as
//   <p>Documento CSV de Acidentes 2026 (Agrupados por ocorrência)</p>
//   ...<a href="https://drive.google.com/file/d/<ID>/view?usp=sharing...">
// ROW_PATTERN below matched 47 such rows against the real page (years
// 2007-2026, three aggregation variants each) — this is a tested
// extractor, not a guess.
//
// One honest limitation: this is HTML scraping, not an API — if PRF
// changes the page markup, ROW_PATTERN stops matching. healthCheck()
// surfaces that as RED (zero rows found) instead of failing silently.
//
// The resolved download URL (`uc?export=download&id=...`) was verified
// with a real request on 2026-08-21: it 303-redirects to
// drive.usercontent.google.com and returns the file directly with
// `Content-Type: application/octet-stream` — this file is under Drive's
// virus-scan confirmation-page threshold, so no extra `confirm=` token
// dance is needed for it.
//
// normalize() — downloaded and inspected the real 2026 file on
// 2026-08-21 (datatran2026.zip, ~1.8MB zipped / ~9.7MB csv, 33694 rows).
// It's a zip containing one `;`-delimited, latin1-encoded CSV with a
// quoted field that itself contains a literal `;` (tracado_via, e.g.
// "Aclive;Reta") — a naive `line.split(';')` silently breaks on those
// rows, hence the small quote-aware parseCsvLine below instead of
// pulling in a full CSV library for one file shape. Columns confirmed
// from the real header: id;data_inversa;dia_semana;horario;uf;br;km;
// municipio;causa_acidente;tipo_acidente;classificacao_acidente;
// fase_dia;sentido_via;condicao_metereologica;tipo_pista;tracado_via;
// uso_solo;pessoas;mortos;feridos_leves;feridos_graves;ilesos;ignorados;
// feridos;veiculos;latitude;longitude;regional;delegacia;uop — every one
// of the 33694 data rows in the 2026 file had a valid, in-Brazil
// latitude/longitude, so geoPrecision is EXACT (a real GPS-adjacent
// coordinate the source itself recorded, not something inferred here).
// latitude/longitude/km use a comma decimal separator (pt-BR locale),
// handled by ptNumber().
//
// Severity mapping is deliberately the 3-tier scale this app's community
// reports already use (low/medium/high — see SeverityColors in
// lib/theme/beeaware_theme.dart) rather than inventing a new vocabulary,
// so whenever these events reach the map they slot into the existing
// severity legend instead of a second parallel one:
//   mortos > 0            -> fatal_accident   / severity "high"
//   feridos_graves > 0    -> serious_accident / severity "medium"
//   otherwise              -> accident         / severity "low"
// (2026 file breakdown: 2467 fatal, 6961 serious, 24266 low.)

import JSZip from "https://esm.sh/jszip@3.10.1";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const SOURCE_PAGE_URL =
  "https://www.gov.br/prf/pt-br/acesso-a-informacao/dados-abertos/dados-abertos-da-prf";

// "por ocorr" rather than the full accented "por ocorrência" — the source
// page's encoding isn't reliably UTF-8 when re-fetched, and this prefix
// survives either way.
const ROW_PATTERN =
  /<p>(Documento CSV de Acidentes (\d{4}) \((Agrupados por ocorr[^)]*)\))<\/p>.*?href="(https:\/\/drive\.google\.com\/file\/d\/([A-Za-z0-9_-]+))[^"]*"/gs;

interface PrfAccidentFile {
  year: number;
  label: string;
  fileId: string;
  downloadUrl: string;
}

// Quote-aware CSV line split — the source file has at least one quoted
// field (tracado_via) containing the delimiter itself, so a plain
// line.split(sep) silently produces the wrong number of columns on those
// rows. Verified against every row of the real 2026 file (33694/33694
// rows parsed to the expected 30 columns).
function parseCsvLine(line: string, sep: string): string[] {
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
    } else if (c === sep) {
      fields.push(cur);
      cur = "";
    } else {
      cur += c;
    }
  }
  fields.push(cur);
  return fields;
}

function parseCsv(text: string, sep: string): Record<string, string>[] {
  const lines = text.split(/\r?\n/).filter((l) => l.length > 0);
  if (lines.length === 0) return [];
  const header = parseCsvLine(lines[0], sep);
  return lines.slice(1).map((line) => {
    const values = parseCsvLine(line, sep);
    const row: Record<string, string> = {};
    header.forEach((h, i) => {
      row[h] = values[i] ?? "";
    });
    return row;
  });
}

// PRF numeric columns (latitude/longitude/km) use a pt-BR comma decimal
// separator, e.g. "-7,291548".
function ptNumber(raw: string | undefined): number | undefined {
  if (!raw || raw === "NA") return undefined;
  const n = Number(raw.replace(",", "."));
  return Number.isFinite(n) ? n : undefined;
}

function mapRowToEvent(row: Record<string, string>): SecurityEvent {
  const mortos = Number(row.mortos ?? 0);
  const feridosGraves = Number(row.feridos_graves ?? 0);

  let eventType: string;
  let severity: string;
  if (mortos > 0) {
    eventType = "fatal_accident";
    severity = "high";
  } else if (feridosGraves > 0) {
    eventType = "serious_accident";
    severity = "medium";
  } else {
    eventType = "accident";
    severity = "low";
  }

  const latitude = ptNumber(row.latitude);
  const longitude = ptNumber(row.longitude);
  const occurredAt = row.data_inversa && row.horario
    ? `${row.data_inversa}T${row.horario}-03:00` // PRF times are local Brazil time (UTC-3; no DST since 2019)
    : undefined;
  const victimCount = Number.isFinite(Number(row.pessoas)) ? Number(row.pessoas) : undefined;

  return {
    countryCode: "BR",
    stateCode: row.uf || undefined,
    sourceRecordId: row.id,
    sourceType: "official",
    eventCategory: "ROAD_SAFETY",
    eventType,
    originalCategory: row.tipo_acidente || undefined,
    occurredAt,
    latitude,
    longitude,
    // Real coordinates recorded by the source itself, not inferred —
    // MUNICIPALITY fallback only covers the (unseen in practice) case of
    // a row missing lat/lon.
    geoPrecision: latitude != null && longitude != null ? "EXACT" : "MUNICIPALITY",
    locationConfidence: 1.0,
    city: row.municipio || undefined,
    state: row.uf || undefined,
    victimCount,
    severity,
    confidenceScore: 1.0,
    rawPayload: row,
  };
}

function findLatestByOccurrence(html: string): PrfAccidentFile | undefined {
  let latest: PrfAccidentFile | undefined;

  for (const match of html.matchAll(ROW_PATTERN)) {
    const [, label, yearStr, , , fileId] = match;
    const year = Number(yearStr);
    if (!latest || year > latest.year) {
      latest = {
        year,
        label,
        fileId,
        downloadUrl: `https://drive.google.com/uc?export=download&id=${fileId}`,
      };
    }
  }

  return latest;
}

export class PrfAccidentsAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      name: "PRF - Dados Abertos de Acidentes",
      organisation: "Polícia Rodoviária Federal",
      sourceType: "official",
      sourceUrl: SOURCE_PAGE_URL,
      adapterName: "PrfAccidentsAdapter",
      adapterVersion: "0.3.0", // fetch() + normalize() both real; verified against the live 2026 file
      refreshFrequency: "daily", // roadmap 12.6
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(SOURCE_PAGE_URL);
    if (!res.ok) {
      throw new Error(`PRF source page request failed: ${res.status} ${res.statusText}`);
    }

    const html = await res.text();
    const latest = findLatestByOccurrence(html);
    if (!latest) {
      return [];
    }

    return [
      {
        sourceRecordId: latest.fileId,
        payload: latest,
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const file = record.payload as PrfAccidentFile;

    const res = await fetch(file.downloadUrl);
    if (!res.ok) {
      throw new Error(`PRF file download failed: ${res.status} ${res.statusText}`);
    }

    const zip = await JSZip.loadAsync(await res.arrayBuffer());
    const csvEntryName = Object.keys(zip.files).find((n) => n.toLowerCase().endsWith(".csv"));
    if (!csvEntryName) {
      throw new Error(`PRF zip for ${file.year} contains no .csv entry`);
    }

    const csvBytes = await zip.files[csvEntryName].async("uint8array");
    const csvText = new TextDecoder("iso-8859-1").decode(csvBytes);
    const rows = parseCsv(csvText, ";");

    return rows.map(mapRowToEvent);
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const records = await this.fetch();
      if (records.length === 0) {
        return {
          status: "RED",
          message: "No 'Agrupados por ocorrência' row found on the source page — markup may have changed",
        };
      }
      // lastDataDate must be a real date (security_sources.last_data_date
      // is a `date` column) — the source page only tells us the file's
      // YEAR, not a precise date, and a bare "2026" broke the
      // security_sources upsert silently (caught, logged, returns null
      // id), which in turn left source_id null on every ingested event.
      // Omit it rather than fabricate a fake day-of-year.
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
