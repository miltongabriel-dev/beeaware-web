// BeeAware Brasil roadmap — IBGE adapter (section 3.2, Phase 1).
//
// IBGE is the territorial identity master: city_ibge_code is the
// canonical municipality key everything else (SINESP, state adapters,
// geo_areas) joins against. This is real, working code — verified live
// against https://servicodados.ibge.gov.br on 2026-08-21 — not a stub.
//
// Population lives on a separate IBGE endpoint (SIDRA aggregates) and is
// still left out. Municipality polygons (the /malhas GeoJSON API) are
// now covered by fetchAndNormalizeGeometry() below — added when the
// RJ-ISP violence choropleth needed real municipality boundaries to
// color. Verified live: GET /api/v3/malhas/estados/{UF}?formato=
// application/vnd.geo+json&intrarregiao=municipio&qualidade=minima
// returns every municipality in that state as one GeoJSON
// FeatureCollection (92 features / 47KB for RJ) with the IBGE code in
// `properties.codarea` — one HTTP call per state rather than one per
// municipality (5570 individual calls would be impractical from a
// single Edge Function invocation).

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
