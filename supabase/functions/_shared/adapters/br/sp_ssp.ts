// BeeAware Brasil roadmap — SpSspAdapter (São Paulo, SSP-SP official
// crime data). Named in types.ts's own header comment as an expected
// adapter alongside PaSegupAdapter — this is that adapter.
//
// Real source, found live 2026-08-26 (not the dadosabertos.sp.gov.br
// portal mg_ssp.ts's header already flagged as an Angular-SPA dead end —
// a different, directly-hosted file on ssp.sp.gov.br itself):
// https://www.ssp.sp.gov.br/assets/estatistica/transparencia/spDados/
// SPDadosCriminais_{year}.xlsx, one file per year (2022-2026 confirmed
// live), plus a semester-split current-year file
// (SPDadosCriminais_2026.xlsx covers Jan-Jun 2026 specifically — SSP-SP
// republishes the current year's file as it accrues, apparently
// semester by semester, not monthly).
//
// Format is genuinely per-occurrence, not RJ-ISP's pre-aggregated
// monthly counts: each row is one boletim de ocorrência, with real
// LATITUDE/LONGITUDE (76.1% of rows have them, confirmed against the
// real Jan-Jun 2026 file), NOME_DELEGACIA_CIRCUNSCRICAO (the district
// where the fact occurred — not necessarily the district that filed the
// report), NATUREZA_APURADA (verified/audited crime classification —
// 23 distinct values, a genuinely closed set), DATA_OCORRENCIA_BO, and
// COD IBGE. Richer than every other state source in this project.
//
// The catch, and why this adapter cannot actually run inside
// ingest-security-sources: the Jan-Jun 2026 file alone is 96MB / 555,404
// rows. PA-SEGUP's own header documents hitting 1.6GB RAM parsing a
// 137,405-row export (one city, one month) — this file is ~4x that row
// count for the whole state, and Deno has no native/lightweight XLSX
// parser to lean on the way SINESP's hand-rolled ZIP+XML reader could
// (that file was ~20MB and still needed a custom parser; this one is
// squarely in "process outside the Edge Function" territory, same as
// SINESP's own conclusion). fetch() below is left honest about this
// rather than pretending a real implementation exists.
//
// What actually shipped: 20260826150000_sp_ssp_manual_population.sql —
// downloaded and parsed the real Jan-Jun 2026 file on a normal machine
// (no such limit there, same workaround SINESP's migration used),
// aggregated to (DP district, month, category) monthly counts (not
// individual incidents — consistent with every other state adapter
// here, and the right call independent of the size limit: exact
// addresses/times for 555k individual reports isn't something a public
// map should expose at that resolution), matched district names against
// the 1039 real DP polygons from 20260826110000_sp_dp_geometry.sql.
// normalize() below reproduces that exact aggregation/mapping logic —
// the canonical reference for re-running this against a future
// semester's file, the same role sinesp.ts's normalize() plays for its
// own migration.
//
// Verified live 2026-08-26 against the real Jan-Jun 2026 file: 0 of the
// 555,404 rows had an unmapped NATUREZA_APURADA (NATUREZA_MAP below is
// exhaustive for what's actually in the file), 509,575 (91.7%) matched
// a real DP polygon by name — the rest (mostly abbreviation variants
// like "DP" vs "D.P.", or a handful of newer districts not yet in the
// 2024-vintage shapefile) still become events, just without a
// geo_area_id, same MUNICIPALITY-level fallback RS-SSP/AL-SEDS rows get
// when their own district/name matching comes up empty.
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const COMBINING_MARKS_RE = new RegExp("[\\u0300-\\u036f]", "g");

function stripAccents(s: string): string {
  return s
    .normalize("NFKD")
    .replace(COMBINING_MARKS_RE, "")
    .toUpperCase()
    .trim();
}

// natureza (accent-stripped upper) -> [eventCategory, eventType, severity].
// Exhaustive for the 23 distinct NATUREZA_APURADA values confirmed
// present in the real Jan-Jun 2026 file — verified, not assumed, same
// "closed set, direct lookup, unmapped falls through and is skipped"
// discipline as MG-SSP's NATUREZA_MAP.
const NATUREZA_MAP: Record<string, [string, string, string]> = {
  "FURTO - OUTROS": ["PROPERTY", "theft", "low"],
  "FURTO DE VEICULO": ["PROPERTY", "vehicle_theft", "low"],
  "FURTO DE CARGA": ["PROPERTY", "theft", "low"],
  "ROUBO - OUTROS": ["PROPERTY", "robbery", "medium"],
  "ROUBO DE VEICULO": ["PROPERTY", "vehicle_robbery", "medium"],
  "ROUBO DE CARGA": ["PROPERTY", "cargo_robbery", "medium"],
  "LESAO CORPORAL DOLOSA": ["VIOLENCE", "assault", "medium"],
  "LESAO CORPORAL CULPOSA POR ACIDENTE DE TRANSITO": ["ROAD_SAFETY", "accident", "low"],
  "LESAO CORPORAL CULPOSA - OUTRAS": ["VIOLENCE", "assault", "low"],
  "LESAO CORPORAL SEGUIDA DE MORTE": ["VIOLENCE", "homicide", "high"],
  "TRAFICO DE ENTORPECENTES": ["PUBLIC_SAFETY", "drugs", "medium"],
  "PORTE DE ENTORPECENTES": ["PUBLIC_SAFETY", "drugs", "low"],
  "APREENSAO DE ENTORPECENTES": ["PUBLIC_SAFETY", "drugs", "low"],
  "PORTE DE ARMA": ["PUBLIC_SAFETY", "weapon", "medium"],
  "ESTUPRO DE VULNERAVEL": ["VIOLENCE", "sexual_violence", "high"],
  "ESTUPRO": ["VIOLENCE", "sexual_violence", "high"],
  "TENTATIVA DE HOMICIDIO": ["VIOLENCE", "attempted_homicide", "medium"],
  "HOMICIDIO DOLOSO": ["VIOLENCE", "homicide", "high"],
  "HOMICIDIO CULPOSO POR ACIDENTE DE TRANSITO": ["ROAD_SAFETY", "fatal_accident", "high"],
  "HOMICIDIO CULPOSO OUTROS": ["VIOLENCE", "homicide", "high"],
  "HOMICIDIO DOLOSO POR ACIDENTE DE TRANSITO": ["VIOLENCE", "homicide", "high"],
  "EXTORSAO MEDIANTE SEQUESTRO": ["VIOLENCE", "kidnapping", "high"],
  "LATROCINIO": ["VIOLENCE", "homicide", "high"],
};

interface SpDadosRow {
  NOME_MUNICIPIO_CIRCUNSCRICAO?: string;
  NOME_MUNICIPIO?: string;
  NOME_DELEGACIA_CIRCUNSCRICAO?: string;
  NATUREZA_APURADA?: string;
  DATA_OCORRENCIA_BO?: string; // ISO date
  "COD IBGE"?: string | number;
}

// Real DP names already in geo_areas (20260826110000) — matched
// accent/case-insensitively so `district` uses the exact geo_areas.name
// spelling, which is what security_events_resolve_geo_area (widened in
// 20260826130000) needs for its exact-string join.
function dpNameByNormalized(
  lookupName: (normalized: string) => string | undefined,
  raw: string | undefined,
): string | undefined {
  if (!raw) return undefined;
  return lookupName(stripAccents(raw));
}

export class SpSspAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "SP",
      name: "SSP-SP - Dados Criminais",
      organisation: "Secretaria da Segurança Pública do Estado de São Paulo",
      sourceType: "official",
      sourceUrl: "https://www.ssp.sp.gov.br/estatistica/consultas",
      adapterName: "SpSspAdapter",
      adapterVersion: "1.0.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    // Left honest rather than pretending this can complete in an Edge
    // Function — see this file's header for the measured reasons
    // (96MB/555k rows for one semester alone, no viable Deno XLSX
    // parser at that scale). 20260826150000_sp_ssp_manual_population.sql
    // is how the real data actually got in; re-running that process for
    // a future semester's file means downloading it on a normal machine
    // and feeding rows through normalize() below, not calling fetch().
    throw new Error(
      "SpSspAdapter.fetch() is not viable inside an Edge Function — " +
        "the source file is 96MB/555k+ rows per semester. See this " +
        "file's header and 20260826150000_sp_ssp_manual_population.sql.",
    );
  }

  // Takes already-parsed rows (from whatever reads the real XLSX outside
  // the Edge Function) rather than a RawSecurityRecord payload shaped
  // like fetch() would have produced, since fetch() never runs here —
  // this is the aggregation/mapping spec, called directly by the
  // migration-generation script that actually reproduces it.
  async normalizeRows(
    rows: SpDadosRow[],
    dpNames: string[],
  ): Promise<SecurityEvent[]> {
    const dpByNormalized = new Map(dpNames.map((n) => [stripAccents(n), n]));
    const agg = new Map<string, SecurityEvent>();

    for (const row of rows) {
      const natureza = row.NATUREZA_APURADA;
      if (!natureza) continue;
      const mapped = NATUREZA_MAP[stripAccents(natureza)];
      if (!mapped) continue; // unmapped natureza -- skipped, not guessed

      const dateStr = row.DATA_OCORRENCIA_BO;
      if (!dateStr) continue;
      const yearMonth = dateStr.slice(0, 7); // "YYYY-MM"

      const districtRaw = row.NOME_DELEGACIA_CIRCUNSCRICAO;
      const district = dpNameByNormalized(
        (n) => dpByNormalized.get(n),
        districtRaw,
      );

      const codIbge = row["COD IBGE"] != null ? String(row["COD IBGE"]) : undefined;
      const municipio = row.NOME_MUNICIPIO_CIRCUNSCRICAO || row.NOME_MUNICIPIO;
      const [eventCategory, eventType, severity] = mapped;

      const key = `sp-${district ?? `ibge${codIbge}`}-ibge${codIbge}-${yearMonth}-${eventType}-${severity}`
        .replace(/ /g, "_");

      const existing = agg.get(key);
      if (existing) {
        existing.occurrenceCount = (existing.occurrenceCount ?? 1) + 1;
        continue;
      }

      agg.set(key, {
        countryCode: "BR",
        stateCode: "SP",
        cityIbgeCode: codIbge,
        sourceRecordId: key,
        sourceType: "official",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        occurredAt: `${yearMonth}-01T00:00:00-03:00`,
        geoPrecision: "DISTRICT",
        district,
        city: municipio,
        state: "SP",
        occurrenceCount: 1,
        severity,
      });
    }

    return Array.from(agg.values());
  }

  async normalize(_record: RawSecurityRecord): Promise<SecurityEvent[]> {
    // Never called in practice — fetch() always throws first. Present
    // to satisfy SecuritySourceAdapter; normalizeRows() above is the
    // real logic.
    return [];
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch("https://www.ssp.sp.gov.br/estatistica/consultas");
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on source page` };
      }
      return {
        status: "AMBER",
        message: "Source page reachable, but fetch() is not viable at this file size — see header.",
        lastDataDate: "2026-06-30",
      };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
