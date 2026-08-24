// BeeAware Brasil roadmap — IBGE adapter (section 3.2, Phase 1).
//
// IBGE is the territorial identity master: city_ibge_code is the
// canonical municipality key everything else (SINESP, state adapters,
// geo_areas) joins against. This is real, working code — verified live
// against https://servicodados.ibge.gov.br on 2026-08-21 — not a stub.
//
// Municipality polygons (the /malhas GeoJSON API) are covered by
// fetchAndNormalizeGeometry() below — added when the RJ-ISP violence
// choropleth needed real municipality boundaries to color. Verified
// live: GET /api/v3/malhas/estados/{UF}?formato=application/vnd.geo+json
// &intrarregiao=municipio&qualidade=minima returns every municipality in
// that state as one GeoJSON FeatureCollection (92 features / 47KB for
// RJ) with the IBGE code in `properties.codarea` — one HTTP call per
// state rather than one per municipality (5570 individual calls would
// be impractical from a single Edge Function invocation).
//
// Population (Safety Pulse / Historical Safety) is covered by
// fetchAndNormalizePopulation() below — IBGE's SIDRA aggregates API,
// table 6579 ("População residente estimada"), variable 9324. Verified
// live 2026-08-24: GET /api/v3/agregados/6579/periodos/-1/variaveis/9324
// ?localidades=N6[N3[{numericUfCode}]] returns every municipality in one
// state with its latest population estimate in one call (confirmed: 52
// municipalities for Rondônia in one response; São Paulo municipality
// alone read 11,904,961 for 2025). Two real quirks found by testing, not
// assumed: the N3 filter needs the numeric IBGE UF code, not the sigla
// (N3[RJ] 500s; N3[33] works — UF_NUMERIC_CODE below) — and there is no
// single national call (N6[N1[1]] returns []), so this needs the same
// per-state loop fetchAndNormalizeGeometry() already uses, not a single
// request.

import type {
  GeoArea,
  RawSecurityRecord,
  SecuritySource,
  SourceHealth,
  TerritorialSourceAdapter,
} from "../types.ts";

const BASE_URL = "https://servicodados.ibge.gov.br/api/v1/localidades";

export interface MunicipalityGeometry {
  cityIbgeCode: string;
  geometry: unknown;
  sourceVersion: string;
}

export interface MunicipalityPopulation {
  cityIbgeCode: string;
  population: number;
}

// IBGE's own numeric UF codes — stable, well-known government codes
// (not a guess), needed because the SIDRA aggregates API's N3 locality
// filter rejects UF sigla (confirmed live: N3[RJ] 500s, N3[33] works).
const UF_NUMERIC_CODE: Record<string, number> = {
  RO: 11, AC: 12, AM: 13, RR: 14, PA: 15, AP: 16, TO: 17,
  MA: 21, PI: 22, CE: 23, RN: 24, PB: 25, PE: 26, AL: 27, SE: 28, BA: 29,
  MG: 31, ES: 32, RJ: 33, SP: 35,
  PR: 41, SC: 42, RS: 43,
  MS: 50, MT: 51, GO: 52, DF: 53,
};

interface IbgeMunicipio {
  id: number;
  nome: string;
  microrregiao?: {
    mesorregiao?: {
      UF?: { id: number; sigla: string; nome: string };
    };
  };
}

export class IbgeAdapter implements TerritorialSourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      name: "IBGE - Localidades",
      organisation: "Instituto Brasileiro de Geografia e Estatística",
      sourceType: "official",
      sourceUrl: BASE_URL,
      adapterName: "IbgeAdapter",
      adapterVersion: "1.0.0",
      refreshFrequency: "monthly", // matches roadmap 12.6's IBGE check cadence
    };
  }

  // stateCode is a UF sigla (e.g. "PA"). Omitting it fetches all ~5,570
  // municipalities in one call (confirmed to work), but scoping to one
  // state keeps ingestion aligned with the roadmap's state-by-state
  // rollout — Pará first (roadmap 11.3).
  async fetch(stateCode?: string): Promise<RawSecurityRecord[]> {
    const url = stateCode
      ? `${BASE_URL}/estados/${stateCode}/municipios`
      : `${BASE_URL}/municipios`;

    const res = await fetch(url);
    if (!res.ok) {
      throw new Error(
        `IBGE municipios request failed: ${res.status} ${res.statusText}`,
      );
    }

    const municipios = (await res.json()) as IbgeMunicipio[];
    const fetchedAt = new Date().toISOString();

    return municipios.map((m) => ({
      sourceRecordId: String(m.id),
      payload: m,
      fetchedAt,
    }));
  }

  normalize(record: RawSecurityRecord): Promise<GeoArea[]> {
    const m = record.payload as IbgeMunicipio;
    const uf = m.microrregiao?.mesorregiao?.UF;

    if (!uf) {
      // Defensive: skip rather than write a geo_area with an unknown
      // state if IBGE ever returns a record without a full UF chain.
      return Promise.resolve([]);
    }

    const area: GeoArea = {
      countryCode: "BR",
      stateCode: uf.sigla,
      cityIbgeCode: String(m.id),
      areaType: "MUNICIPALITY",
      name: m.nome,
      source: "IBGE",
      sourceVersion: record.fetchedAt,
    };

    return Promise.resolve([area]);
  }

  // Not part of TerritorialSourceAdapter — this backfills geometry onto
  // municipality rows that already exist (from fetch()/normalize()
  // above), it doesn't create new geo_areas rows, so it doesn't fit the
  // fetch-then-normalize shape. Called directly by the ingestion
  // function's geometry-backfill path, one state at a time.
  async fetchAndNormalizeGeometry(stateCode: string): Promise<MunicipalityGeometry[]> {
    const url =
      `https://servicodados.ibge.gov.br/api/v3/malhas/estados/${stateCode}` +
      `?formato=application/vnd.geo+json&intrarregiao=municipio&qualidade=minima`;

    const res = await fetch(url);
    if (!res.ok) {
      throw new Error(`IBGE malha request failed for ${stateCode}: ${res.status} ${res.statusText}`);
    }

    const geojson = (await res.json()) as {
      features: { properties: { codarea: string }; geometry: unknown }[];
    };
    const sourceVersion = new Date().toISOString();

    return geojson.features.map((f) => ({
      cityIbgeCode: f.properties.codarea,
      geometry: f.geometry,
      sourceVersion,
    }));
  }

  // Not part of TerritorialSourceAdapter — same reasoning as
  // fetchAndNormalizeGeometry above: backfills onto existing geo_areas
  // rows rather than creating new ones. One state at a time, matching
  // the geometry method's shape (called from index.ts's
  // backfill-population action, looping all 27 UFs).
  async fetchAndNormalizePopulation(stateCode: string): Promise<MunicipalityPopulation[]> {
    const ufCode = UF_NUMERIC_CODE[stateCode];
    if (!ufCode) {
      throw new Error(`IBGE population: unknown UF sigla "${stateCode}"`);
    }

    const url =
      `https://servicodados.ibge.gov.br/api/v3/agregados/6579/periodos/-1/variaveis/9324` +
      `?localidades=N6[N3[${ufCode}]]`;

    const res = await fetch(url);
    if (!res.ok) {
      throw new Error(`IBGE population request failed for ${stateCode}: ${res.status} ${res.statusText}`);
    }

    const data = (await res.json()) as {
      resultados: { series: { localidade: { id: string }; serie: Record<string, string> }[] }[];
    }[];

    const series = data[0]?.resultados[0]?.series ?? [];
    const results: MunicipalityPopulation[] = [];
    for (const s of series) {
      // `serie` is keyed by year (periodos=-1 asks for the single latest
      // one, but the key itself varies year to year — read whichever key
      // is actually present rather than hardcoding a year).
      const [population] = Object.values(s.serie);
      const n = Number(population);
      if (!Number.isFinite(n) || n <= 0) continue; // skip rather than write a bad value
      results.push({ cityIbgeCode: s.localidade.id, population: n });
    }
    return results;
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(`${BASE_URL}/estados`);
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status}` };
      }
      return { status: "GREEN", lastDataDate: new Date().toISOString() };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
