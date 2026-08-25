// BeeAware Brasil roadmap — RJ ISP adapter (state-level violence data,
// roadmap 4.3's "PaSegupAdapter, SpSspAdapter..." pattern — this is the
// first real one, for Rio de Janeiro).
//
// SINESP (the national violence/crime source) is blocked — its resource
// download links point at a dead domain (see sinesp.ts). Individual
// states publish their own open data instead, and Rio de Janeiro's ISP
// (Instituto de Segurança Pública) is one of the most complete: verified
// live on 2026-08-21, https://www.ispdados.rj.gov.br/Arquivos/
// BaseDPEvolucaoMensalCisp.csv is a real, current, `;`-delimited,
// latin1-encoded CSV — 38136 rows, monthly counts per police district
// (CISP) from 2003-01 to 2026-07, columns confirmed from the real
// header: cisp;mes;ano;mes_ano;aisp;risp;munic;mcirc;regiao;hom_doloso;
// lesao_corp_morte;latrocinio;cvli;hom_por_interv_policial;feminicidio;
// letalidade_violenta;tentat_hom;tentativa_feminicidio;lesao_corp_dolosa;
// estupro;...;roubo_veiculo;...;furto_veiculos;...;trafico_drogas;...
//
// This is fundamentally different from PRF: it's a monthly aggregate
// count per police district, not a per-occurrence record with a real
// location — individual violent-crime records with addresses aren't
// published anywhere (understandably, for victim safety). So there is
// no lat/lon here, and occurrenceCount carries the actual count.
//
// One row per (CISP, month, event type) — not aggregated up to
// municipality — now that real CISP boundaries exist in geo_areas
// (20260825210000/220000/230000_rj_*_geometry.sql, from ISP's own
// RISPkml/AISPkml/CISPkml exports). `district` is set to "CISP {id}",
// the exact string those migrations used for geo_areas.name, so the
// security_events_resolve_geo_area trigger (20260825250000) links each
// event to its real polygon automatically on insert — no lookup needed
// here. Verified live 2026-08-25 against the real CSV's most recent
// 24-month window (what MONTHS_WINDOW below actually processes): all
// 137 CISPs in that window have a matching KML polygon and vice versa
// (exact 1:1), and every CISP maps to exactly one municipality (`mcirc`)
// throughout the window — so cityIbgeCode/cityName are kept alongside
// the new district/CISP fields, not replaced by them; both a
// municipality-level and (once geo_area_id resolves) a CISP-level query
// stay meaningful.
//
// This is a scope change from the previous municipality-aggregated
// version: existing MUNICIPALITY-precision rows from RjIspAdapter are
// deleted by 20260825260000_rj_isp_reprocess_cleanup.sql alongside this
// change, since their sourceRecordId format (keyed by municipality) has
// no relationship to the new CISP-keyed one and would otherwise sit
// alongside the new rows as stale duplicates, double-counting anything
// that aggregates by municipality.
//
// Only the last 24 months are ingested — the file's full 23-year history
// is real but not useful for a "how risky is this area right now"
// choropleth, and keeps ingestion volume reasonable (~16k aggregate rows
// for 24 months across ~82 municipalities, verified against the real
// file, vs. ~380k if every column/month/CISP combination since 2003 were
// kept).

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const SOURCE_URL = "https://www.ispdados.rj.gov.br/Arquivos/BaseDPEvolucaoMensalCisp.csv";
const MONTHS_WINDOW = 24;

// column -> [eventCategory, eventType] — mapped onto the existing
// taxonomy (supabase/functions/_shared/taxonomy.ts) rather than
// inventing RJ-specific types. Columns not listed here (e.g. cvli,
// letalidade_violenta, which are themselves sums of other columns; or
// administrative counts like apf, registro_ocorrencias) are skipped to
// avoid double-counting or including non-crime figures.
const COLUMN_MAP: Record<string, [string, string]> = {
  hom_doloso: ["VIOLENCE", "homicide"],
  latrocinio: ["VIOLENCE", "homicide"],
  feminicidio: ["VIOLENCE", "homicide"],
  tentat_hom: ["VIOLENCE", "attempted_homicide"],
  hom_por_interv_policial: ["VIOLENCE", "police_intervention"],
  lesao_corp_dolosa: ["VIOLENCE", "assault"],
  estupro: ["VIOLENCE", "sexual_violence"],
  sequestro: ["VIOLENCE", "kidnapping"],
  sequestro_relampago: ["VIOLENCE", "kidnapping"],
  roubo_veiculo: ["PROPERTY", "vehicle_robbery"],
  roubo_carga: ["PROPERTY", "cargo_robbery"],
  roubo_celular: ["PROPERTY", "phone_robbery"],
  roubo_residencia: ["PROPERTY", "burglary"],
  total_roubos: ["PROPERTY", "robbery"],
  furto_veiculos: ["PROPERTY", "vehicle_theft"],
  furto_celular: ["PROPERTY", "phone_theft"],
  total_furtos: ["PROPERTY", "theft"],
  trafico_drogas: ["PUBLIC_SAFETY", "drugs"],
};

const HIGH_SEVERITY = new Set(["homicide", "attempted_homicide", "sexual_violence", "kidnapping"]);
const LOW_SEVERITY = new Set(["theft", "vehicle_theft", "phone_theft"]);

function severityFor(eventType: string): string {
  if (HIGH_SEVERITY.has(eventType)) return "high";
  if (LOW_SEVERITY.has(eventType)) return "low";
  return "medium";
}

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

function yearMonth(row: Record<string, string>): string {
  return `${row.ano}-${row.mes.padStart(2, "0")}`;
}

interface AggregateGroup {
  cispId: string;
  cityIbgeCode: string;
  cityName: string;
  yearMonth: string;
  eventCategory: string;
  eventType: string;
  occurrenceCount: number;
}

export class RjIspAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "RJ",
      name: "ISP-RJ - Evolução Mensal CISP",
      organisation: "Instituto de Segurança Pública do Rio de Janeiro",
      sourceType: "official",
      sourceUrl: SOURCE_URL,
      adapterName: "RjIspAdapter",
      adapterVersion: "0.2.0", // CISP-level rows instead of municipality-aggregated
      refreshFrequency: "monthly", // ISP publishes a monthly update
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(SOURCE_URL);
    if (!res.ok) {
      throw new Error(`ISP-RJ CSV request failed: ${res.status} ${res.statusText}`);
    }

    const bytes = new Uint8Array(await res.arrayBuffer());
    const text = new TextDecoder("iso-8859-1").decode(bytes);

    return [
      {
        sourceRecordId: "isp-rj-cisp-monthly",
        payload: text,
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const csvText = record.payload as string;
    const rows = parseCsv(csvText, ";");
    if (rows.length === 0) return Promise.resolve([]);

    let maxYm = "0000-00";
    for (const row of rows) {
      const ym = yearMonth(row);
      if (ym > maxYm) maxYm = ym;
    }
    const [maxY, maxM] = maxYm.split("-").map(Number);
    const cutoff = new Date(maxY, maxM - 1 - (MONTHS_WINDOW - 1), 1);
    const cutoffYm = `${cutoff.getFullYear()}-${String(cutoff.getMonth() + 1).padStart(2, "0")}`;

    const groups = new Map<string, AggregateGroup>();

    for (const row of rows) {
      const ym = yearMonth(row);
      if (ym < cutoffYm) continue;

      const cispId = row.cisp;
      const cityIbgeCode = row.mcirc;
      const cityName = row.munic;
      if (!cispId || !cityIbgeCode) continue;

      for (const [column, [eventCategory, eventType]] of Object.entries(COLUMN_MAP)) {
        const raw = row[column];
        if (raw === "" || raw == null) continue;
        const n = Number(raw);
        if (!Number.isFinite(n) || n <= 0) continue;

        const key = `${cispId}|${ym}|${eventCategory}|${eventType}`;
        const existing = groups.get(key);
        if (existing) {
          existing.occurrenceCount += n;
        } else {
          groups.set(key, {
            cispId,
            cityIbgeCode,
            cityName,
            yearMonth: ym,
            eventCategory,
            eventType,
            occurrenceCount: n,
          });
        }
      }
    }

    const districtLocationConfidence = defaultLocationConfidence("DISTRICT");

    const events: SecurityEvent[] = Array.from(groups.values()).map((g) => ({
      countryCode: "BR",
      stateCode: "RJ",
      cityIbgeCode: g.cityIbgeCode,
      sourceRecordId: `cisp${g.cispId}-${g.yearMonth}-${g.eventType}`,
      sourceType: "official",
      eventCategory: g.eventCategory as SecurityEvent["eventCategory"],
      eventType: g.eventType,
      occurredAt: `${g.yearMonth}-01T00:00:00-03:00`,
      geoPrecision: "DISTRICT",
      locationConfidence: districtLocationConfidence,
      district: `CISP ${g.cispId}`,
      city: g.cityName,
      state: "RJ",
      occurrenceCount: g.occurrenceCount,
      severity: severityFor(g.eventType),
      confidenceScore: computeConfidenceScore({
        reliabilityGrade: "official_confirmed_record",
        locationConfidence: districtLocationConfidence,
      }),
    }));

    return Promise.resolve(events);
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(SOURCE_URL, { method: "HEAD" });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on source CSV` };
      }
      const lastModified = res.headers.get("last-modified");
      return {
        status: "GREEN",
        lastDataDate: lastModified ? new Date(lastModified).toISOString() : undefined,
      };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
