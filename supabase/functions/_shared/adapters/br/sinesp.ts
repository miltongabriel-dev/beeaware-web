// BeeAware Brasil roadmap — SINESP adapter (section 3.1, Phase 1).
//
// Full trail from a broken adapter to a working one, verified live on
// 2026-08-21:
//   - The roadmap's own URL (gov.br/mj/.../suaseguranca/...) 404s — the
//     path changed to .../sua-seguranca/... (hyphenated).
//   - The legacy CKAN API (dados.gov.br/api/3/action/...) 401s no matter
//     what — it turns out dados.gov.br migrated to a NEW REST API
//     ("API REST do Portal de Dados Abertos", OpenAPI spec at
//     https://dados.gov.br/v3/api-docs) with a completely different auth
//     header and no relation to the old CKAN path.
//   - That spec's securitySchemes says the real header name is
//     `chave-api-dados-abertos` (an apiKey header) — not `Authorization`,
//     `Bearer`, or any of the other names tried before finding the spec.
//     With SINESP_DADOS_GOV_BR_TOKEN sent on that header, dataset search
//     and dataset detail BOTH work (confirmed: `pagina` is 1-indexed —
//     `pagina=0` 400s).
//   - The SINESP dataset id is 210b9ae2-21fc-4986-89c6-2006eb4db247
//     ("Ocorrências Criminais - Sinesp"). Its resource list is real and
//     current (last file update 30/04/2026 per the API) — a "Base de
//     Dados VDE" ZIP (2015-2026) plus per-municipality and per-UF XLSX
//     indicator files.
//   - BUT: every resource's `link` field points at
//     dados.mj.gov.br/dataset/.../download/... — and that domain no
//     longer resolves (DNS failure), a leftover from before the portal
//     consolidated into dados.gov.br. The same path on dados.gov.br 401s
//     with the legacy Bearer challenge again, and the 20 documented
//     `/dados/api/*` routes in the OpenAPI spec don't include a generic
//     "download this resource" endpoint. So: metadata access is real and
//     working; bulk file download is not — that's a stale link in the
//     government's own data, not something to route around by guessing
//     further.
//   - Re-verified 2026-08-21 (second pass): tried the same dados.gov.br
//     path with three auth styles server-side — `chave-api-dados-abertos`
//     (the working header for the metadata API), `Authorization: Bearer
//     <token>`, and no auth at all. All three: 401. The legacy download
//     path isn't gated by an API-key-reachable scheme at all — it almost
//     certainly needs an actual logged-in browser session (a cookie from
//     the dados.gov.br web UI), which no API token can produce. This is a
//     genuine gap in what the government publishes programmatically, not
//     a header/format guess away from working.
//
// normalize() stays a stub for the same reason RENAEST's does: nothing
// has actually been downloaded and inspected yet.

import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const API_BASE = "https://dados.gov.br/dados/api/publico/conjuntos-dados";
const SINESP_DATASET_ID = "210b9ae2-21fc-4986-89c6-2006eb4db247";

interface DatasetResource {
  id: string;
  titulo: string;
  formato: string;
  link: string;
  descricao: string;
  dataUltimaAtualizacaoArquivo: string;
}

interface DatasetDetail {
  id: string;
  titulo: string;
  dataUltimaAtualizacaoArquivo: string;
  dataUltimaAtualizacaoMetadados: string;
  recursos: DatasetResource[];
}

function authHeaders(): HeadersInit {
  const token = Deno.env.get("SINESP_DADOS_GOV_BR_TOKEN");
  return token ? { "chave-api-dados-abertos": token } : {};
}

// dados.gov.br's API returns dataUltimaAtualizacaoArquivo as "DD/MM/YYYY"
// (pt-BR locale), not ISO — a bare pt-BR date string broke the PRF
// adapter's security_sources upsert the same way (that column is a
// Postgres `date`, and "30/04/2026" isn't valid ISO input). Convert
// defensively rather than repeat that bug; if the format ever changes
// unexpectedly, drop it instead of risking another silent upsert failure.
function toIsoDate(raw: string | undefined): string | undefined {
  if (!raw) return undefined;
  const match = raw.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (match) {
    const [, dd, mm, yyyy] = match;
    return `${yyyy}-${mm}-${dd}`;
  }
  return /^\d{4}-\d{2}-\d{2}/.test(raw) ? raw : undefined;
}

export class SinespAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      name: "SINESP VDE",
      organisation: "Ministério da Justiça e Segurança Pública",
      sourceType: "official",
      sourceUrl: `${API_BASE}/${SINESP_DATASET_ID}`,
      adapterName: "SinespAdapter",
      adapterVersion: "0.3.0", // metadata access real; file download still blocked (see header)
      refreshFrequency: "daily", // roadmap 12.6
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(`${API_BASE}/${SINESP_DATASET_ID}`, {
      headers: authHeaders(),
    });
    if (!res.ok) {
      throw new Error(
        `SINESP dataset detail request failed: ${res.status} ${res.statusText}`,
      );
    }

    const detail = (await res.json()) as DatasetDetail;
    const fetchedAt = new Date().toISOString();

    return detail.recursos.map((r) => ({
      sourceRecordId: r.id,
      payload: r,
      fetchedAt,
    }));
  }

  normalize(_record: RawSecurityRecord): Promise<SecurityEvent[]> {
    // TODO: blocked on the dead dados.mj.gov.br download links described
    // in the file header — nothing has been downloaded to map real
    // columns from yet. Once a working download path exists, map the
    // per-municipality/per-UF indicator files onto SecurityEvent as
    // aggregate/baseline records (roadmap 3.1: "not a source of exact
    // incident pins").
    return Promise.resolve([]);
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(`${API_BASE}/${SINESP_DATASET_ID}`, {
        headers: authHeaders(),
      });
      if (!res.ok) {
        return {
          status: "RED",
          message: `HTTP ${res.status} on dataset metadata (auth or dataset id issue)`,
        };
      }
      const detail = (await res.json()) as DatasetDetail;
      // Metadata access works; still AMBER, not GREEN — the resource
      // links it returns are currently unreachable (see file header).
      return {
        status: "AMBER",
        lastDataDate: toIsoDate(detail.dataUltimaAtualizacaoArquivo),
        message: "Metadata OK; resource download links point at a dead domain (dados.mj.gov.br)",
      };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
