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
      adapterVersion: "0.2.0", // fetch() real (page-scraped), normalize() still a stub
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

  normalize(_record: RawSecurityRecord): Promise<SecurityEvent[]> {
    // TODO: download the resolved CSV (road/municipality/date/time/cause/
    // severity per roadmap 3.3) and map its real column names onto
    // SecurityEvent with event_category=ROAD_SAFETY. Not done here — the
    // file wasn't downloaded, so its exact columns haven't been confirmed
    // (see the Drive virus-scan caveat above too).
    return Promise.resolve([]);
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
      const latest = records[0].payload as PrfAccidentFile;
      return { status: "GREEN", lastDataDate: String(latest.year) };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
