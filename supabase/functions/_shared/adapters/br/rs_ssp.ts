// BeeAware Brasil roadmap — RsSspAdapter (Rio Grande do Sul, SSP-RS
// open crime data).
//
// The strongest and simplest source found in this investigation:
// state law 15.610/2021 requires SSP-RS to publish crime data, and
// unlike PA-SEGUP there's no session/CSRF dance — https://www.ssp.rs.gov.br
// /dados-abertos links straight to a ZIP, no login. Verified live on
// 2026-08-21: the current file (jan-jul 2026) is a real, current,
// `;`-delimited, latin1-encoded CSV — 439400 rows, per-occurrence (not
// pre-aggregated like RJ-ISP), covering all 497 municipalities of RS,
// with 112 columns (confirmed: every row has exactly 112 fields, no
// quoting/embedded delimiters — unlike PRF's CSV, a plain split(';') is
// safe here). Real columns confirmed from the header: Sequência;Data
// Fato;Hora Fato;Grupo Fato;Tipo Enquadramento;Tipo Fato;Municipio
// Fato;Local Fato;Bairro;Quantidade Vítimas;Idade Vítima;Sexo
// Vítima;Cor Vítima;... (the rest of the 112 columns are blank in every
// row sampled — reserved/unused by the source, not something this
// adapter needs).
//
// No latitude/longitude column (same as RJ-ISP) — individual records
// with addresses aren't published, so like RJ this becomes municipality-
// level aggregate events (geoPrecision MUNICIPALITY, occurrenceCount),
// feeding the same municipality_crime_summary choropleth, not map pins.
//
// Two real engineering constraints, found by measuring, not guessing:
//   1. The page links to a NEW file each month (filename embeds the
//      period, e.g. "...ocorrencias-jan-jul-2026..."), so fetch() has to
//      discover the current link the same way prf.ts discovers PRF's
//      current-year file — picking the entry with the highest embedded
//      year rather than a fixed URL.
//   2. Memory: this genuinely failed once in production. The first
//      version unzipped with jszip (the same library prf.ts and
//      pa_segup.ts use) and hit WORKER_RESOURCE_LIMIT on the real
//      439400-row file (~95MB decompressed from a ~9MB download) — a
//      jszip-based local repro held ~260-320MB RSS decompressing it,
//      confirming that was the cause, not something else in the
//      request. Fixed two ways: (a) locateSingleZipEntry()/
//      inflateZipEntry() below read the ZIP's central directory by hand
//      and decompress via the platform's own DecompressionStream
//      ("deflate-raw") instead of a JS zip library — a Node zlib repro
//      of the same file measured ~145MB RSS, roughly half; (b)
//      normalize() never materializes an array of parsed row objects
//      (RS has ~30x more rows than PA's Belém pull did) — it scans the
//      decompressed buffer byte-by-byte for line breaks and aggregates
//      directly, so nothing but the decompressed buffer itself and the
//      (much smaller) aggregate Map is held at once.
//
// Tipo Enquadramento has 281 distinct real values in the current file —
// far too many to hand-map one by one like RJ-ISP's 18 columns, so
// CLASSIFY_RULES below is a priority-ordered keyword matcher instead.
// It covers 59.9% of real rows (measured against the actual file, not
// estimated) — the uncovered ~40% is dominated by ESTELIONATO/fraud
// (~72k rows) and INJURIA/CALUNIA/DIFAMACAO (defamation, ~18k rows),
// neither of which has an honest fit in this app's VIOLENCE/PROPERTY/
// PUBLIC_SAFETY/ROAD_SAFETY taxonomy — skipped rather than force-mapped
// onto a category that would misrepresent what happened.
//
// Municipality names in the source are plain uppercase text (no IBGE
// code), so normalize() fetches IBGE's own RS municipality list to
// build a name -> city_ibge_code lookup (normalizing accents/case on
// both sides) — confirmed live: 492 of 497 real municipality names
// matched automatically; the 5 that didn't (alternate spellings like
// "SANTANA DO LIVRAMENTO" vs IBGE's "Sant'Ana do Livramento") are
// skipped rather than guessed.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const PAGE_URL = "https://www.ssp.rs.gov.br/dados-abertos";
const IBGE_MUNICIPIOS_URL = "https://servicodados.ibge.gov.br/api/v1/localidades/estados/RS/municipios";
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";

const LINK_PATTERN =
  /href="(\/upload\/arquivos\/\d+\/\d+-spj-dados-abertos-ocorrencias-jan-[a-z]+-(\d{4})[^"]*\.zip)"/gi;

interface OcorrenciasFile {
  year: number;
  url: string;
}

function findLatestOcorrenciasFile(html: string): OcorrenciasFile | undefined {
  let latest: OcorrenciasFile | undefined;
  for (const match of html.matchAll(LINK_PATTERN)) {
    const [, path, yearStr] = match;
    const year = Number(yearStr);
    if (!latest || year > latest.year) {
      latest = { year, url: `https://www.ssp.rs.gov.br${path}` };
    }
  }
  return latest;
}

function stripAccentsUpper(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().trim();
}

type ClassifyRule = [RegExp, string, string];

// Priority order matters — more specific rules (e.g. traffic-related
// homicide/injury) must come before their general counterparts.
const CLASSIFY_RULES: ClassifyRule[] = [
  [/HOMICIDIO|FEMINICIDIO|LATROCINIO|MORTE DECORRENTE/, "__HOMICIDIO__", "__HOMICIDIO__"], // handled specially below (traffic split)
  [/ESTUPRO/, "VIOLENCE", "sexual_violence"],
  [/SEQUESTRO/, "VIOLENCE", "kidnapping"],
  [/MEDIDA PROTETIVA|VIOLENCIA PSICOLOGICA|VIOLENCIA DOMESTICA|VIOLENCIA FISICA/, "VIOLENCE", "domestic_violence"],
  [/LESAO CORPORAL/, "__LESAO__", "__LESAO__"], // handled specially below (traffic split)
  [/VIAS DE FATO/, "VIOLENCE", "assault"],
  [/ROUBO.*VEICULO|VEICULO.*ROUBO/, "PROPERTY", "vehicle_robbery"],
  [/ROUBO.*CELULAR/, "PROPERTY", "phone_robbery"],
  [/ROUBO.*CARGA/, "PROPERTY", "cargo_robbery"],
  [/ROUBO.*RESIDENCIA/, "PROPERTY", "burglary"],
  [/ROUBO/, "PROPERTY", "robbery"],
  [/FURTO.*VEICULO/, "PROPERTY", "vehicle_theft"],
  [/FURTO.*CELULAR/, "PROPERTY", "phone_theft"],
  [/FURTO.*(RESIDENCIA|ARROMBAMENTO)/, "PROPERTY", "burglary"],
  [/FURTO/, "PROPERTY", "theft"],
  [/ENTORPECENTES|TRAFICO.*DROGA/, "PUBLIC_SAFETY", "drugs"],
  [/ARMA DE FOGO|ARMA BRANCA|DISPARO DE ARMA/, "PUBLIC_SAFETY", "weapon"],
  [/INCENDIO/, "PUBLIC_SAFETY", "fire"],
  [/TRANSITO|DIRECAO|HABILITACAO|EMBRIAGUEZ|VELOCIDADE|\bRACHA\b|ACIDENTE/, "ROAD_SAFETY", "accident"],
  [/AMEACA|PERSEGUICAO|INTIMIDACAO|BULLYING|ASSEDIO|CONSTRANGIMENTO|PERTURBACAO/, "PUBLIC_SAFETY", "disturbance"],
];

const TRAFFIC_HINT = /TRANSITO|DIRECAO VEIC/;

function classify(tipoEnquadramento: string): [string, string] | undefined {
  const t = tipoEnquadramento.toUpperCase();
  for (const [pattern, category, type] of CLASSIFY_RULES) {
    if (!pattern.test(t)) continue;
    if (category === "__HOMICIDIO__") {
      return TRAFFIC_HINT.test(t) ? ["ROAD_SAFETY", "fatal_accident"] : ["VIOLENCE", "homicide"];
    }
    if (category === "__LESAO__") {
      return TRAFFIC_HINT.test(t) ? ["ROAD_SAFETY", "serious_accident"] : ["VIOLENCE", "assault"];
    }
    return [category, type];
  }
  return undefined;
}

const HIGH_SEVERITY = new Set(["homicide", "sexual_violence", "kidnapping", "fatal_accident"]);
const LOW_SEVERITY = new Set(["theft"]);

function severityFor(eventType: string): string {
  if (HIGH_SEVERITY.has(eventType)) return "high";
  if (LOW_SEVERITY.has(eventType)) return "low";
  return "medium";
}

// DD/MM/YYYY -> YYYY-MM
function toYearMonth(dataFato: string): string | undefined {
  const parts = dataFato.split("/");
  if (parts.length !== 3) return undefined;
  const [dd, mm, yyyy] = parts;
  if (!dd || !mm || !yyyy) return undefined;
  return `${yyyy}-${mm}`;
}

interface AggregateGroup {
  cityIbgeCode: string;
  cityName: string;
  yearMonth: string;
  eventCategory: string;
  eventType: string;
  occurrenceCount: number;
}

export class RsSspAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "RS",
      name: "SSP-RS - Dados Abertos de Ocorrências",
      organisation: "Secretaria da Segurança Pública do Rio Grande do Sul",
      sourceType: "official",
      sourceUrl: PAGE_URL,
      adapterName: "RsSspAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly", // matches the source's own publication cadence (Lei 15.610/2021, Art. 3)
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const pageRes = await fetch(PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!pageRes.ok) {
      throw new Error(`SSP-RS page request failed: ${pageRes.status}`);
    }
    const html = await pageRes.text();
    const latest = findLatestOcorrenciasFile(html);
    if (!latest) {
      return [];
    }

    const zipRes = await fetch(latest.url, { headers: { "User-Agent": USER_AGENT } });
    if (!zipRes.ok) {
      throw new Error(`SSP-RS file download failed: ${zipRes.status}`);
    }

    return [
      {
        sourceRecordId: latest.url,
        payload: new Uint8Array(await zipRes.arrayBuffer()),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const municipioToIbgeCode = await fetchMunicipioNameMap();

    const zipBytes = record.payload as Uint8Array;
    const entry = locateSingleZipEntry(zipBytes);

    const groups = new Map<string, AggregateGroup>();
    let firstLineSkipped = false;

    await forEachDecompressedLine(zipBytes, entry, (line) => {
      if (!firstLineSkipped) {
        firstLineSkipped = true;
        return;
      }

      const fields = line.split(";");
      const dataFato = fields[1];
      const tipoEnquadramento = fields[4];
      const municipioFato = fields[6];

      const yearMonth = toYearMonth(dataFato);
      const cityIbgeCode = municipioToIbgeCode.get(stripAccentsUpper(municipioFato ?? ""));
      const mapped = tipoEnquadramento ? classify(tipoEnquadramento) : undefined;

      if (!yearMonth || !cityIbgeCode || !mapped) return;

      const [eventCategory, eventType] = mapped;
      const key = `${cityIbgeCode}|${yearMonth}|${eventCategory}|${eventType}`;
      const existing = groups.get(key);
      if (existing) {
        existing.occurrenceCount += 1;
      } else {
        groups.set(key, {
          cityIbgeCode,
          cityName: municipioFato,
          yearMonth,
          eventCategory,
          eventType,
          occurrenceCount: 1,
        });
      }
    });

    const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");

    return Array.from(groups.values()).map((g) => ({
      countryCode: "BR",
      stateCode: "RS",
      cityIbgeCode: g.cityIbgeCode,
      sourceRecordId: `${g.cityIbgeCode}-${g.yearMonth}-${g.eventType}`,
      sourceType: "official",
      eventCategory: g.eventCategory as SecurityEvent["eventCategory"],
      eventType: g.eventType,
      occurredAt: `${g.yearMonth}-01T00:00:00-03:00`,
      geoPrecision: "MUNICIPALITY",
      locationConfidence: municipalityLocationConfidence,
      city: g.cityName,
      state: "RS",
      occurrenceCount: g.occurrenceCount,
      severity: severityFor(g.eventType),
      confidenceScore: computeConfidenceScore({
        reliabilityGrade: "official_confirmed_record",
        locationConfidence: municipalityLocationConfidence,
      }),
    }));
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on source page` };
      }
      const html = await res.text();
      const latest = findLatestOcorrenciasFile(html);
      if (!latest) {
        return { status: "RED", message: "No ocorrências file link found — page markup may have changed" };
      }
      return { status: "GREEN", lastDataDate: `${latest.year}-01-01` };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}

// Manual ZIP parsing + native DecompressionStream instead of a JS zip
// library (jszip, used by prf.ts and pa_segup.ts) — measured necessity,
// not preference. JSZip decompressing this file held ~260-320MB of RSS
// in local testing (its own JS-implemented inflate plus a full parsed
// object model of the archive), and the deployed function failed with
// WORKER_RESOURCE_LIMIT at that scope. Reading the ZIP's central
// directory by hand to locate the one compressed member, then piping it
// through the platform's own DecompressionStream ("deflate-raw" —
// confirmed this file's compression method is 8/deflate, and its local
// file header's compressed-size field is 0 because the general-purpose
// flag's data-descriptor bit is set, so the size has to come from the
// central directory instead, not the local header) measured at ~145MB
// RSS for the same file locally (Node's zlib as a stand-in for Deno's
// native decompressor) — headroom that actually fits.
interface ZipEntryLocation {
  compressedOffset: number;
  compressedSize: number;
  method: number;
}

function locateSingleZipEntry(zipBytes: Uint8Array): ZipEntryLocation {
  const view = new DataView(zipBytes.buffer, zipBytes.byteOffset, zipBytes.byteLength);

  const EOCD_SIGNATURE = 0x06054b50;
  let eocdOffset = -1;
  const searchStart = Math.max(0, zipBytes.length - 65557); // EOCD + max comment length
  for (let i = zipBytes.length - 22; i >= searchStart; i--) {
    if (view.getUint32(i, true) === EOCD_SIGNATURE) {
      eocdOffset = i;
      break;
    }
  }
  if (eocdOffset === -1) {
    throw new Error("SSP-RS zip: End Of Central Directory record not found");
  }

  const centralDirOffset = view.getUint32(eocdOffset + 16, true);
  const CENTRAL_DIR_SIGNATURE = 0x02014b50;
  if (view.getUint32(centralDirOffset, true) !== CENTRAL_DIR_SIGNATURE) {
    throw new Error("SSP-RS zip: central directory signature mismatch");
  }

  const method = view.getUint16(centralDirOffset + 10, true);
  const compressedSize = view.getUint32(centralDirOffset + 20, true);
  const localHeaderOffset = view.getUint32(centralDirOffset + 42, true);

  const LOCAL_FILE_SIGNATURE = 0x04034b50;
  if (view.getUint32(localHeaderOffset, true) !== LOCAL_FILE_SIGNATURE) {
    throw new Error("SSP-RS zip: local file header signature mismatch");
  }
  const nameLength = view.getUint16(localHeaderOffset + 26, true);
  const extraLength = view.getUint16(localHeaderOffset + 28, true);
  const compressedOffset = localHeaderOffset + 30 + nameLength + extraLength;

  return { compressedOffset, compressedSize, method };
}

function concatUint8Arrays(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

// Genuinely necessary, not just tidy: collecting the whole decompressed
// stream into one buffer first (as inflateZipEntry() used to, and as
// prf.ts/pa_segup.ts both do for their much smaller files) still failed
// with WORKER_RESOURCE_LIMIT for this file even after switching from
// jszip to DecompressionStream — measured locally at ~400MB RSS via
// Response.arrayBuffer() on the full stream, worse than jszip, not
// better (buffering the whole stream adds its own overhead on top of
// the ~95MB payload). Reading the stream chunk by chunk and calling
// onLine() per complete line, discarding each chunk immediately after,
// bounds peak memory to roughly one chunk plus the aggregate Map,
// independent of the file's total size.
async function forEachDecompressedLine(
  zipBytes: Uint8Array,
  entry: ZipEntryLocation,
  onLine: (line: string) => void,
): Promise<void> {
  const compressed = zipBytes.subarray(entry.compressedOffset, entry.compressedOffset + entry.compressedSize);

  let stream: ReadableStream<Uint8Array>;
  if (entry.method === 0) {
    stream = new Blob([compressed]).stream();
  } else if (entry.method === 8) {
    stream = new Blob([compressed]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  } else {
    throw new Error(`SSP-RS zip: unsupported compression method ${entry.method} (expected 0=stored or 8=deflate)`);
  }

  const reader = stream.getReader();
  const decoder = new TextDecoder("iso-8859-1");
  let leftover = new Uint8Array(0);

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    const chunk = leftover.length > 0 ? concatUint8Arrays(leftover, value) : value;
    let start = 0;
    for (;;) {
      const newlineIndex = chunk.indexOf(10, start);
      if (newlineIndex === -1) {
        leftover = chunk.subarray(start);
        break;
      }
      let lineEnd = newlineIndex;
      if (lineEnd > start && chunk[lineEnd - 1] === 13) lineEnd--;
      if (lineEnd > start) {
        onLine(decoder.decode(chunk.subarray(start, lineEnd)));
      }
      start = newlineIndex + 1;
    }
  }

  if (leftover.length > 0) {
    onLine(decoder.decode(leftover));
  }
}

async function fetchMunicipioNameMap(): Promise<Map<string, string>> {
  const res = await fetch(IBGE_MUNICIPIOS_URL);
  if (!res.ok) {
    throw new Error(`IBGE RS municipios request failed: ${res.status}`);
  }
  const municipios = (await res.json()) as { id: number; nome: string }[];
  return new Map(municipios.map((m) => [stripAccentsUpper(m.nome), String(m.id)]));
}
