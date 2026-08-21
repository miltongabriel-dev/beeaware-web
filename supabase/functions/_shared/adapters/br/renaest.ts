// BeeAware Brasil roadmap — RENAEST adapter (section 3.4, Phase 1).
//
// RENAEST publishes monthly ZIP files (Sinistros / Localidade /
// TipoVeiculo / Vitimas) through a CKAN portal. fetch() is real, working
// code — verified live on 2026-08-21 against:
//   https://dados.transportes.gov.br/api/3/action/package_show?id=renaest
// which returned HTTP 200 with a resource list including a ZIP dated
// 2026-08-18 (~500MB). CKAN's package_show is the whole point here: it
// lets fetch() always resolve the *current* file without hardcoding a URL
// that will go stale next month.
//
// normalize() is intentionally a stub. RENAEST's CSV column names inside
// that ZIP have not been inspected yet (the files are large — several
// hundred MB — so pulling and parsing one wasn't done as part of this
// pass); write the real field mapping once a sample has been opened.

import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const PACKAGE_URL =
  "https://dados.transportes.gov.br/api/3/action/package_show?id=renaest";

interface CkanResource {
  id: string;
  name: string;
  format: string;
  url: string;
  created: string;
  size?: number;
}

interface CkanPackageShowResponse {
  success: boolean;
  result: { resources: CkanResource[] };
}

export class RenaestAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      name: "RENAEST",
      organisation: "SENATRAN - Secretaria Nacional de Trânsito",
      sourceType: "official",
      sourceUrl: PACKAGE_URL,
      adapterName: "RenaestAdapter",
      adapterVersion: "0.1.0", // fetch() real, normalize() still a stub
      refreshFrequency: "weekly", // roadmap 12.6
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(PACKAGE_URL);
    if (!res.ok) {
      throw new Error(
        `RENAEST CKAN package_show failed: ${res.status} ${res.statusText}`,
      );
    }

    const body = (await res.json()) as CkanPackageShowResponse;
    if (!body.success) {
      throw new Error("RENAEST CKAN package_show returned success=false");
    }

    const zipResources = body.result.resources
      .filter((r) => r.format?.toUpperCase() === "ZIP")
      .sort((a, b) => b.created.localeCompare(a.created));

    const latest = zipResources[0];
    if (!latest) {
      return [];
    }

    // Downloading and unzipping the ~500MB monthly package is deliberately
    // NOT done inside fetch() here — that belongs in the ingestion job
    // once normalize() knows what to do with its contents. This just
    // resolves *which* file is current right now.
    return [
      {
        sourceRecordId: latest.id,
        payload: latest,
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  normalize(_record: RawSecurityRecord): Promise<SecurityEvent[]> {
    // TODO: download the resolved ZIP, read Sinistros/Localidade/
    // TipoVeiculo/Vitimas, and map their real column names onto
    // SecurityEvent (event_category=ROAD_SAFETY) once a sample has been
    // inspected. Returning [] rather than guessing at column names that
    // would silently produce wrong data.
    return Promise.resolve([]);
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const records = await this.fetch();
      if (records.length === 0) {
        return { status: "AMBER", message: "No ZIP resource found in CKAN package" };
      }
      const latest = records[0].payload as CkanResource;
      return { status: "GREEN", lastDataDate: latest.created };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
