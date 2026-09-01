// BeeAware Global blueprint — MadridAccidentsAdapter, the first genuine
// per-incident (not aggregate) point source for Spain, and the direct
// answer to "why don't PT/ES have hexagon pins like Brazil/UK": their
// NATIONAL crime statistics bodies (Portugal's DGPJ, Spain's Ministerio
// del Interior) only ever publish periodic aggregate counts by area —
// never a per-occurrence record with a real coordinate. City-level open
// data portals are a different story: Madrid's own Ayuntamiento
// publishes a real per-accident dataset (Policía Municipal de Madrid),
// one row per PERSON involved (so several rows per accident), with a
// real recorded coordinate, address, date/time and injury outcome per
// accident — the same shape as prf.ts's own EXACT-precision Brazilian
// federal-highway accidents, just for Madrid's city streets instead.
//
// Investigated live (2026-09-01): tried a dedicated Spanish national
// "sucesos"-style open dataset first (nothing found, same conclusion as
// es_news.ts's own header) then looked at CITY open data portals
// instead — Barcelona's Guàrdia Urbana has an equally real per-accident
// dataset (accidents-gu-bcn) but only publishes once a YEAR, months after
// it closes (the 2025 file only appeared in February 2026, no 2026 file
// exists yet) — not "frequent" enough to be worth ingesting yet. Madrid's
// own dataset, by contrast, is updated roughly monthly: confirmed live,
// the current resource (found via the CKAN API below) covered accidents
// through 30 June 2026, only ~2 months behind "now" — comparable lag to
// UkPoliceAdapter's own data.police.uk.
//
// Coverage is scoped to the city of Madrid only (not all of Spain, and
// only traffic accidents, not crime in general) — a real, accepted
// narrowing, the same kind of documented partial-coverage tradeoff as
// PrSespAdapter's PR-only scope or MaSspAdapter's Grande São Luís-only
// scope elsewhere in this project.
//
// The dataset's own CKAN resource IDs churn every month (Madrid appears
// to publish a brand NEW resource each month rather than updating one in
// place — confirmed live: the "current year" CSV resource id changed
// from 300228-1 to 300228-34 between two checks days apart, with the
// underlying filename itself embedding the month, e.g.
// "accidentes-trafico-pmm-junio-2026.csv"). Hardcoding a resource id
// would go stale within weeks, so fetch() always resolves it dynamically
// via the CKAN package_show API: filter resources to format='CSV' with a
// real last_modified, sort by last_modified descending, take the first
// — this is robust to the portal creating a new resource id every month
// without this adapter needing to track exactly when.
//
// The CSV is genuine UTF-8 (Content-Type's own `charset=utf-8` is
// correct) prefixed with a UTF-8 BOM (EF BB BF) — stripped from the raw
// bytes before decoding, not after: decoding those 3 bytes AS the text
// itself (rather than recognising and removing them first) turns them
// into three mangled characters in front of the first column name
// instead of a clean "num_expediente", which broke column lookup and
// crashed the whole adapter on the first real run (a bare 500 with no
// useful message — tracked down by replaying this exact fetch()/decode
// logic locally against a saved copy of the real file).
//
// A second, distinct mojibake bug showed up only once actually deployed
// (never reproduced testing the identical bytes locally in Node): every
// accented character came back double-UTF-8-encoded (e.g. "Ã³" instead
// of "ó" — the literal 2-byte UTF-8 sequence for "ó", C3 B3, decoded a
// SECOND time as if it were itself already text). fixMojibake() below
// detects and reverses this unconditionally-safe way (Spanish text never
// legitimately contains "Ã" on its own) rather than depending on
// tracking down which exact runtime step reintroduces it.
//
// coordenada_x_utm/coordenada_y_utm are ETRS89 UTM zone 30N (EPSG:25830)
// — confirmed live against a real address (Calle de Goya 46, Madrid)
// using pyproj as an independent reference before writing the
// dependency-free conversion below (utmZone30nToWgs84), which matches
// pyproj's EPSG:25830 output to 5 decimal places on that same point.
// WGS84/UTM30N (EPSG:32630) gives an identical result at this precision
// (the ETRS89/WGS84 divergence is sub-meter in Spain), so no import is
// needed for a Deno Edge Function to do this conversion correctly.
//
// One row per PERSON involved, not per accident (num_expediente repeats
// — a 3-person collision is 3 rows with identical location/time). fetch()
// groups by num_expediente and picks the WORST lesividad (injury outcome)
// across the group to classify the whole accident, the same "don't let
// an uninjured passenger's empty lesividad hide a fatality elsewhere in
// the same accident" reasoning as any per-victim source.
//
// fetch() returns exactly ONE RawSecurityRecord (the whole month's worth
// of accidents as its payload array) rather than one per accident — the
// same shape as UkPoliceAdapter/NiPoliceAdapter (one record per
// force/council, normalize() expands it into many events), not
// PrfAccidentsAdapter's one-record-per-row shape. Found live: an earlier
// version returned one RawSecurityRecord per accident (~11,500 of them
// for a single 6-month file) and every real run then hung/500'd with no
// useful error — persistRawEvents' own raw_events insert
// (ingest-security-sources/index.ts) is a single unbatched INSERT
// covering every record fetch() returns, unlike the SecurityEvent
// upsert loop three lines below it (EVENT_BATCH_SIZE=500) — so ~11,500
// raw_events rows in one statement is exactly the kind of load that
// batched path was built to avoid, just hit from the fetch() side
// instead of the normalize() side. One record with an array payload
// keeps raw_events' own insert trivially small while still letting the
// existing per-event batching handle the ~11,500 actual SecurityEvent
// rows normalize() produces.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const PACKAGE_URL = "https://datos.madrid.es/api/3/action/package_show?id=300228-0-accidentes-trafico-detalle";
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";

interface CkanResource {
  format?: string;
  url?: string;
  last_modified?: string | null;
}

// See file header — reverses an unwanted second UTF-8 encode pass by
// treating the (wrongly) decoded string as Latin-1 bytes and decoding
// those as UTF-8 again. Only invoked when "Ã" is actually present, so a
// correctly-decoded string is never touched.
function fixMojibake(text: string): string {
  if (!text.includes("Ã") && !text.includes("Â")) return text;
  const bytes = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) bytes[i] = text.charCodeAt(i) & 0xff;
  return new TextDecoder("utf-8").decode(bytes);
}

async function findLatestCsvUrl(): Promise<string> {
  const res = await fetch(PACKAGE_URL, { headers: { "User-Agent": USER_AGENT } });
  if (!res.ok) throw new Error(`package_show failed: ${res.status}`);
  const body = (await res.json()) as { result?: { resources?: CkanResource[] } };
  const resources = body.result?.resources ?? [];
  const csvResources = resources.filter(
    (r) => (r.format ?? "").toUpperCase() === "CSV" && r.last_modified,
  );
  if (csvResources.length === 0) throw new Error("no CSV resource with last_modified found");
  csvResources.sort((a, b) => (b.last_modified! > a.last_modified! ? 1 : -1));
  const url = csvResources[0].url;
  if (!url) throw new Error("latest CSV resource has no url");
  return url;
}

// Standard UTM inverse (Snyder) formula, WGS84/GRS80 ellipsoid — verified
// live against pyproj's EPSG:25830 transform (see file header). Zone 30N
// is hardcoded since every Madrid accident falls in that single zone.
function utmZone30nToWgs84(easting: number, northing: number): { lat: number; lng: number } {
  const a = 6378137.0;
  const f = 1 / 298.257223563;
  const k0 = 0.9996;
  const e = Math.sqrt(f * (2 - f));
  const e1sq = (e * e) / (1 - e * e);
  const x = easting - 500000.0;
  const y = northing;
  const m = y / k0;
  const mu = m / (a * (1 - (e * e) / 4 - (3 * e ** 4) / 64 - (5 * e ** 6) / 256));
  const e1 = (1 - Math.sqrt(1 - e * e)) / (1 + Math.sqrt(1 - e * e));
  const j1 = (3 * e1) / 2 - (27 * e1 ** 3) / 32;
  const j2 = (21 * e1 ** 2) / 16 - (55 * e1 ** 4) / 32;
  const j3 = (151 * e1 ** 3) / 96;
  const j4 = (1097 * e1 ** 4) / 512;
  const fp = mu + j1 * Math.sin(2 * mu) + j2 * Math.sin(4 * mu) + j3 * Math.sin(6 * mu) + j4 * Math.sin(8 * mu);

  const e2 = e * e;
  const c1 = e2 * Math.cos(fp) ** 2;
  const t1 = Math.tan(fp) ** 2;
  const r1 = (a * (1 - e2)) / Math.pow(1 - e2 * Math.sin(fp) ** 2, 1.5);
  const n1 = a / Math.sqrt(1 - e2 * Math.sin(fp) ** 2);
  const d = x / (n1 * k0);

  const q1 = (n1 * Math.tan(fp)) / r1;
  const q2 = (d * d) / 2;
  const q3 = ((5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * e1sq) * d ** 4) / 24;
  const q4 = ((61 + 90 * t1 + 298 * c1 + 45 * t1 * t1 - 252 * e1sq - 3 * c1 * c1) * d ** 6) / 720;
  const lat = fp - q1 * (q2 - q3 + q4);

  const q6 = ((1 + 2 * t1 + c1) * d ** 3) / 6;
  const q7 = ((5 - 2 * c1 + 28 * t1 - 3 * c1 * c1 + 8 * e1sq + 24 * t1 * t1) * d ** 5) / 120;
  const lon = (d - q6 + q7) / Math.cos(fp);

  const zoneCentralMeridian = (30 - 1) * 6 - 180 + 3;
  return { lat: (lat * 180) / Math.PI, lng: (lon * 180) / Math.PI + zoneCentralMeridian };
}

// Worst-first — see file header on why the whole accident is classified
// by its most severe involved person, not the first row encountered.
const LESIVIDAD_SEVERITY: [string, string][] = [
  ["Fallecido", "high"],
  ["Ingreso superior a 24 horas", "high"],
  ["Ingreso inferior o igual a 24 horas", "medium"],
  ["Asistencia sanitaria inmediata en centro de salud o mutua", "medium"],
  ["Atención en urgencias sin posterior ingreso", "medium"],
  ["Asistencia sanitaria ambulatoria con posterioridad", "low"],
  ["Asistencia sanitaria sólo en el lugar del accidente", "low"],
  ["Sin asistencia sanitaria", "low"],
];

function classifyLesividades(lesividades: string[]): { eventType: string; severity: string } {
  for (const [needle, severity] of LESIVIDAD_SEVERITY) {
    if (lesividades.some((l) => l.startsWith(needle))) {
      return { eventType: needle === "Fallecido" ? "fatal_accident" : "accident", severity };
    }
  }
  return { eventType: "accident", severity: "low" };
}

interface AccidentPayload {
  expediente: string;
  lat: number;
  lng: number;
  occurredAt: string;
  distrito: string;
  tipoAccidente: string;
  eventType: string;
  severity: string;
  victimCount: number;
}

// DD/MM/YYYY + H:MM:SS (Madrid local time, no leading zero guaranteed on
// the hour) -> an ISO string. Treated as UTC, same simplification every
// other adapter in this project already makes for occurred_at (a few
// hours of timezone offset doesn't change which month/recency-window
// bucket an event falls in, which is the only thing occurred_at drives
// downstream).
function parseFechaHora(fecha: string, hora: string): string | undefined {
  const fechaMatch = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(fecha.trim());
  const horaMatch = /^(\d{1,2}):(\d{2}):(\d{2})$/.exec(hora.trim());
  if (!fechaMatch || !horaMatch) return undefined;
  const [, day, month, year] = fechaMatch;
  const [, hour, minute, second] = horaMatch;
  return `${year}-${month}-${day}T${hour.padStart(2, "0")}:${minute}:${second}Z`;
}

export class MadridAccidentsAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "ES",
      name: "Accidentes de tráfico de la ciudad de Madrid",
      organisation: "Policía Municipal de Madrid (Ayuntamiento de Madrid)",
      sourceType: "official",
      sourceUrl: "https://datos.madrid.es/dataset/300228-0-accidentes-trafico-detalle",
      adapterName: "MadridAccidentsAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "weekly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const csvUrl = await findLatestCsvUrl();
    const res = await fetch(csvUrl, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) throw new Error(`CSV download failed: ${res.status}`);
    let bytes = new Uint8Array(await res.arrayBuffer());
    // See file header on both the BOM and the mojibake fix below.
    if (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
      bytes = bytes.slice(3);
    }
    const text = fixMojibake(new TextDecoder("utf-8").decode(bytes));

    const lines = text.split("\n").filter((l) => l.trim().length > 0);
    if (lines.length < 2) return [];
    const header = lines[0].split(";").map((h) => h.trim());
    const col = (name: string) => header.indexOf(name);
    const iExpediente = col("num_expediente");
    const iFecha = col("fecha");
    const iHora = col("hora");
    const iDistrito = col("distrito");
    const iTipo = col("tipo_accidente");
    const iLesividad = col("lesividad");
    const iX = col("coordenada_x_utm");
    const iY = col("coordenada_y_utm");
    if ([iExpediente, iFecha, iHora, iDistrito, iTipo, iLesividad, iX, iY].some((i) => i === -1)) {
      throw new Error("expected column missing — Madrid CSV structure may have changed");
    }

    interface Accum {
      fecha: string;
      hora: string;
      distrito: string;
      tipo: string;
      x: string;
      y: string;
      lesividades: string[];
    }
    const byExpediente = new Map<string, Accum>();

    for (let i = 1; i < lines.length; i++) {
      const cells = lines[i].split(";");
      if (cells.length <= Math.max(iExpediente, iFecha, iHora, iDistrito, iTipo, iLesividad, iX, iY)) continue;
      const expediente = cells[iExpediente].trim();
      if (!expediente) continue;
      const lesividad = cells[iLesividad].trim();

      let acc = byExpediente.get(expediente);
      if (!acc) {
        acc = {
          fecha: cells[iFecha].trim(),
          hora: cells[iHora].trim(),
          distrito: cells[iDistrito].trim(),
          tipo: cells[iTipo].trim(),
          x: cells[iX].trim(),
          y: cells[iY].trim(),
          lesividades: [],
        };
        byExpediente.set(expediente, acc);
      }
      if (lesividad) acc.lesividades.push(lesividad);
    }

    const accidents: AccidentPayload[] = [];
    for (const [expediente, acc] of byExpediente) {
      const xNum = Number(acc.x.replace(",", "."));
      const yNum = Number(acc.y.replace(",", "."));
      if (!Number.isFinite(xNum) || !Number.isFinite(yNum)) continue;
      const occurredAt = parseFechaHora(acc.fecha, acc.hora);
      if (!occurredAt) continue;

      const { lat, lng } = utmZone30nToWgs84(xNum, yNum);
      const { eventType, severity } = classifyLesividades(acc.lesividades);

      accidents.push({
        expediente,
        lat,
        lng,
        occurredAt,
        distrito: acc.distrito,
        tipoAccidente: acc.tipo,
        eventType,
        severity,
        victimCount: acc.lesividades.length,
      });
    }

    if (accidents.length === 0) return [];
    return [
      {
        sourceRecordId: `madrid-accidents-${csvUrl}`,
        payload: accidents,
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const accidents = record.payload as AccidentPayload[];
    const locationConfidence = defaultLocationConfidence("EXACT");

    const events: SecurityEvent[] = accidents.map((payload) => ({
      countryCode: "ES",
      sourceRecordId: `madrid-accidents-${payload.expediente}`,
      sourceType: "official",
      eventCategory: "ROAD_SAFETY",
      eventType: payload.eventType,
      originalCategory: payload.tipoAccidente,
      occurredAt: payload.occurredAt,
      latitude: payload.lat,
      longitude: payload.lng,
      geoPrecision: "EXACT",
      locationConfidence,
      district: payload.distrito,
      city: "Madrid",
      state: "Comunidad de Madrid",
      occurrenceCount: 1,
      victimCount: payload.victimCount,
      severity: payload.severity,
      confidenceScore: computeConfidenceScore({
        reliabilityGrade: "official_confirmed_record",
        locationConfidence,
      }),
    }));

    return Promise.resolve(events);
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const csvUrl = await findLatestCsvUrl();
      const res = await fetch(csvUrl, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on CSV` };
      }
      const match = /(\d{4})\.csv$|-(\w+)-(\d{4})\.csv$/.exec(csvUrl);
      return { status: "GREEN", lastDataDate: match ? `${match[3] ?? match[1]}-01-01` : undefined };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
