// BeeAware Brasil roadmap — PaSegupAdapter (Pará, SEGUP open crime data).
//
// The best source found so far: unlike RJ-ISP (rj_isp.ts, aggregate
// monthly counts only), SEGUP-PA's portal (codec.segup.pa.gov.br)
// publishes real PER-OCCURRENCE crime records with an actual latitude/
// longitude — verified live on 2026-08-21 against real Belém exports
// (every row had coordinates, in both a 3-month and a 1-month pull).
// That means this source can become real map pins (EXACT precision) via
// the existing nearby_security_events RPC / BrazilSecurityApi — no
// separate choropleth-style consumption needed on the client, unlike
// RJ-ISP.
//
// The catch: this isn't a clean JSON API, it's a Django-rendered search
// form (POST / with a CSRF token + session cookie) whose result triggers
// a second endpoint (GET /download_recorte) that regenerates an XLSX
// export server-side from whatever the last search in that session was.
// Reverse-engineered by hand from the real page/JS (no guessing):
//   - GET / for a fresh csrfmiddlewaretoken (in the HTML) and a
//     `csrftoken`/`sessionid` cookie pair.
//   - GET /api/bairros — real endpoint, returns every {municipios,
//     bairros, risp} pair in the state (2262 rows) — used to discover
//     which neighbourhoods belong to the target municipality, since the
//     search form requires at least one lista_bairros value or it 400s
//     with "Certifique-se que todas as caixas foram selecionadas
//     corretamente" (confirmed by testing: omitting bairros entirely
//     fails; selecting every bairro for the chosen municipality works).
//   - POST / with lista_municipios, lista_bairros (all of the target
//     municipality's), lista_consolidados (all 18 crime types — CONSOLIDADOS
//     below), data_inicio/data_fim and the CSRF token, using the same
//     session cookie.
//   - GET /download_recorte with the same session cookie returns the
//     XLSX for whatever was just searched.
//
// Scope is deliberately narrow: Belém only (not all 145 municipalities),
// and a trailing 1-month window (not the full history back to 2010, and
// not even the 3 months first tried). Two real, measured constraints
// drove this, not caution for its own sake — both found by actually
// hitting them in production, not estimated in advance:
//   1. Memory: parsing the full-state, full-year export (137405 rows)
//      used 1.6GB of RAM in Node — far past what an Edge Function has.
//      Belém alone for 3 months (8083 rows, the first scope tried) made
//      the deployed function fail outright with
//      `WORKER_RESOURCE_LIMIT: not having enough compute resources`.
//      1 month (~1000-1100 rows for Belém) is the scope that actually
//      ran to completion — confirmed live: 1010 events normalized, 1008
//      written (2 fingerprint collisions, see sourceRecordId below).
//   2. Latency: /download_recorte regenerates the file server-side on
//      every request — observed anywhere from ~60s to 500s+ even for
//      this narrower scope, occasionally hitting a plain timeout during
//      testing. The full fetch() flow here (4 sequential requests, the
//      last one being the slow one) can plausibly approach an Edge
//      Function's execution limit on a slow day. This is a real, known
//      fragility of the government's own server, not something fixable
//      from the client side — if a scheduled run fails, healthCheck()
//      reports RED and the next scheduled run just tries again (weekly,
//      not daily — see the ingest-pa-segup-weekly cron job; the trailing
//      1-month window overlaps the previous run's, so a missed week
//      doesn't lose data, it just re-covers it next time).
//
// normalize() maps CONSOLIDADO(S) (Pará's own crime-type labels) onto
// the existing taxonomy — see CONSOLIDADO_MAP. Traffic-related labels
// (HOMICIDIO CULPOSO NO TRANSITO, LESAO NO TRANSITO, MORTE NO TRANSITO)
// go to ROAD_SAFETY, not VIOLENCE, matching the taxonomy's own split.
// There is no unique ID column in the source data, so sourceRecordId is
// a composite fingerprint of the fields that identify an occurrence
// (neighbourhood, date, time, crime type/specification, coordinates,
// victim age/sex) — the same "verified in practice" limitation UkPoliceApi
// already accepts: two genuinely distinct occurrences sharing every one
// of those fields would collide and dedupe as one. Rare (2 collisions in
// 1010 real events, ~0.2%), and an accepted tradeoff rather than an
// invented random ID that would defeat idempotent upserts entirely.
// This collision rate is also what surfaced a real bug in the shared
// ingestion code, not just a theoretical risk: Postgres rejects an
// entire multi-row upsert if two rows in the same call share a conflict
// key ("ON CONFLICT DO UPDATE command cannot affect row a second time"),
// which was silently failing whole 500-row batches. Fixed in
// ingest-security-sources/index.ts's runEventAdapter (dedupe by
// source_record_id before batching) rather than here, since it's a
// correctness issue for any adapter with a non-trivial collision rate,
// not something specific to this source.

import * as XLSX from "https://esm.sh/xlsx@0.18.5";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const BASE_URL = "https://codec.segup.pa.gov.br/";
const DOWNLOAD_URL = "https://codec.segup.pa.gov.br/download_recorte";
const BAIRROS_API_URL = "https://codec.segup.pa.gov.br/api/bairros";
const MUNICIPALITY = "BELEM";
const MONTHS_WINDOW = 1;
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";

// Every "Consolidados" checkbox value on the real search form, in the
// order they appear in the page.
const CONSOLIDADOS = [
  "ESTUPRO",
  "ESTUPRO DE VULNERAVEL",
  "ESTUPRO COM RESULTADO MORTE",
  "ESTUPRO DE VULNERAVEL COM RESULTADO MORTE",
  "EXTORSAO MEDIANTE SEQUESTRO COM RESULTADO MORTE",
  "FEMINICIDIO",
  "FURTO",
  "HOMICIDIO",
  "HOMICIDIO CULPOSO NO TRANSITO",
  "LATROCINIO",
  "LESAO CORPORAL",
  "LESAO CORPORAL SEGUIDA DE MORTE",
  "LESAO NO TRANSITO",
  "MAUS TRATOS COM RESULTADO MORTE",
  "MORTE NO TRANSITO",
  "MORTE POR INTERVENCAO DE AGENTE DO ESTADO",
  "ROUBO",
  "TRAFICO DE DROGAS",
];

const CONSOLIDADO_MAP: Record<string, [string, string]> = {
  "ESTUPRO": ["VIOLENCE", "sexual_violence"],
  "ESTUPRO DE VULNERAVEL": ["VIOLENCE", "sexual_violence"],
  "ESTUPRO COM RESULTADO MORTE": ["VIOLENCE", "homicide"],
  "ESTUPRO DE VULNERAVEL COM RESULTADO MORTE": ["VIOLENCE", "homicide"],
  "EXTORSAO MEDIANTE SEQUESTRO COM RESULTADO MORTE": ["VIOLENCE", "homicide"],
  "FEMINICIDIO": ["VIOLENCE", "homicide"],
  "FURTO": ["PROPERTY", "theft"],
  "HOMICIDIO": ["VIOLENCE", "homicide"],
  "HOMICIDIO CULPOSO NO TRANSITO": ["ROAD_SAFETY", "fatal_accident"],
  "LATROCINIO": ["VIOLENCE", "homicide"],
  "LESAO CORPORAL": ["VIOLENCE", "assault"],
  "LESAO CORPORAL SEGUIDA DE MORTE": ["VIOLENCE", "homicide"],
  "LESAO NO TRANSITO": ["ROAD_SAFETY", "serious_accident"],
  "MAUS TRATOS COM RESULTADO MORTE": ["VIOLENCE", "homicide"],
  "MORTE NO TRANSITO": ["ROAD_SAFETY", "fatal_accident"],
  "MORTE POR INTERVENCAO DE AGENTE DO ESTADO": ["VIOLENCE", "police_intervention"],
  "ROUBO": ["PROPERTY", "robbery"],
  "TRAFICO DE DROGAS": ["PUBLIC_SAFETY", "drugs"],
};

const HIGH_SEVERITY = new Set(["homicide", "sexual_violence", "police_intervention", "fatal_accident"]);
const LOW_SEVERITY = new Set(["theft"]);

function severityFor(eventType: string): string {
  if (HIGH_SEVERITY.has(eventType)) return "high";
  if (LOW_SEVERITY.has(eventType)) return "low";
  return "medium";
}

interface Bairro {
  risp: string;
  municipios: string;
  bairros: string;
}

function formatDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

// Cookie parsing/serialising kept minimal on purpose — Deno's fetch has
// no built-in cookie jar (unlike a browser), and this only ever needs to
// track two cookies (csrftoken, sessionid) across three requests in the
// same flow.
function mergeCookies(existing: Map<string, string>, setCookieHeaders: string[]): void {
  for (const header of setCookieHeaders) {
    const [pair] = header.split(";");
    const eq = pair.indexOf("=");
    if (eq === -1) continue;
    existing.set(pair.slice(0, eq).trim(), pair.slice(eq + 1).trim());
  }
}

function cookieHeader(cookies: Map<string, string>): string {
  return [...cookies.entries()].map(([k, v]) => `${k}=${v}`).join("; ");
}

// Excel's date epoch is 1899-12-30 (not 1900-01-01 — this already bakes
// in Excel's own leap-year bug, which is what makes this the correct
// conversion for values Excel itself produced).
function excelSerialToIsoDate(serial: number): string {
  const epochMs = Date.UTC(1899, 11, 30);
  return new Date(epochMs + serial * 86400000).toISOString().slice(0, 10);
}

function ptNumber(raw: unknown): number | undefined {
  if (typeof raw !== "string" || raw === "") return undefined;
  const n = Number(raw.replace(",", "."));
  return Number.isFinite(n) ? n : undefined;
}

export class PaSegupAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "PA",
      name: "SEGUP-PA - Estatística Criminal (Belém)",
      organisation: "Secretaria de Estado de Segurança Pública e Defesa Social do Pará",
      sourceType: "official",
      sourceUrl: BASE_URL,
      adapterName: "PaSegupAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "weekly", // the source's own generation latency makes daily impractical
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const homeRes = await fetch(BASE_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!homeRes.ok) {
      throw new Error(`SEGUP-PA home page request failed: ${homeRes.status}`);
    }
    const homeHtml = await homeRes.text();
    const tokenMatch = homeHtml.match(/csrfmiddlewaretoken" value="([^"]+)"/);
    if (!tokenMatch) {
      throw new Error("SEGUP-PA home page did not contain a csrfmiddlewaretoken");
    }

    const cookies = new Map<string, string>();
    mergeCookies(cookies, homeRes.headers.getSetCookie());

    const bairrosRes = await fetch(BAIRROS_API_URL, {
      headers: { "User-Agent": USER_AGENT, Cookie: cookieHeader(cookies) },
    });
    if (!bairrosRes.ok) {
      throw new Error(`SEGUP-PA /api/bairros request failed: ${bairrosRes.status}`);
    }
    const allBairros = (await bairrosRes.json()) as Bairro[];
    const municipalityBairros = allBairros
      .filter((b) => b.municipios === MUNICIPALITY)
      .map((b) => b.bairros);
    if (municipalityBairros.length === 0) {
      throw new Error(`SEGUP-PA /api/bairros returned no neighbourhoods for ${MUNICIPALITY}`);
    }

    const now = new Date();
    const start = new Date(now);
    start.setMonth(start.getMonth() - MONTHS_WINDOW);

    const params = new URLSearchParams();
    params.append("csrfmiddlewaretoken", tokenMatch[1]);
    params.append("lista_municipios", MUNICIPALITY);
    for (const b of municipalityBairros) params.append("lista_bairros", b);
    for (const c of CONSOLIDADOS) params.append("lista_consolidados", c);
    params.append("data_inicio", formatDate(start));
    params.append("data_fim", formatDate(now));
    params.append("btn-pesquisa", "BUSCAR");

    const searchRes = await fetch(BASE_URL, {
      method: "POST",
      headers: {
        "User-Agent": USER_AGENT,
        "Content-Type": "application/x-www-form-urlencoded",
        Cookie: cookieHeader(cookies),
        Referer: BASE_URL,
        Origin: "https://codec.segup.pa.gov.br",
      },
      body: params.toString(),
    });
    if (!searchRes.ok) {
      throw new Error(`SEGUP-PA search request failed: ${searchRes.status}`);
    }
    const searchHtml = await searchRes.text();
    if (!searchHtml.includes("PESQUISA REALIZADA COM SUCESSO")) {
      throw new Error("SEGUP-PA search did not report success — form fields may have changed");
    }
    mergeCookies(cookies, searchRes.headers.getSetCookie());

    const downloadRes = await fetch(DOWNLOAD_URL, {
      headers: { "User-Agent": USER_AGENT, Cookie: cookieHeader(cookies), Referer: BASE_URL },
    });
    if (!downloadRes.ok) {
      throw new Error(`SEGUP-PA download request failed: ${downloadRes.status}`);
    }

    const bytes = new Uint8Array(await downloadRes.arrayBuffer());

    return [
      {
        sourceRecordId: `${MUNICIPALITY}-${formatDate(start)}-${formatDate(now)}`,
        payload: bytes,
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const bytes = record.payload as Uint8Array;
    const workbook = XLSX.read(bytes, { type: "array" });
    const sheet = workbook.Sheets[workbook.SheetNames[0]];
    const rows = XLSX.utils.sheet_to_json(sheet, { defval: null }) as Record<string, unknown>[];

    const events: SecurityEvent[] = [];

    for (const row of rows) {
      const consolidado = row["CONSOLIDADO(S)"] as string | null;
      const mapped = consolidado ? CONSOLIDADO_MAP[consolidado] : undefined;
      if (!mapped) continue; // unmapped/unexpected label — skip rather than guess a category

      const latitude = ptNumber(row["LATITUDE"]);
      const longitude = ptNumber(row["LONGITUDE"]);
      if (latitude == null || longitude == null) continue;

      const [eventCategory, eventType] = mapped;
      const dateSerial = row["DATA DO FATO"];
      const hora = (row["HORA DO FATO"] as string) || "00:00:00";
      const occurredAt = typeof dateSerial === "number"
        ? `${excelSerialToIsoDate(dateSerial)}T${hora}-03:00`
        : undefined;

      const bairro = (row["BAIRRO(S)"] as string) ?? "";
      const especificacao = (row["ESPECIFICAÇÃO CRIME"] as string) ?? "";
      const idadeVitima = row["IDADE VÍTIMA"] ?? "";
      const sexoVitima = (row["SEXO VÍTIMA"] as string) ?? "";

      events.push({
        countryCode: "BR",
        stateCode: "PA",
        sourceRecordId:
          `${bairro}|${dateSerial}|${hora}|${consolidado}|${especificacao}|${latitude}|${longitude}|${idadeVitima}|${sexoVitima}`,
        sourceType: "official",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        originalCategory: especificacao || consolidado || undefined,
        occurredAt,
        latitude,
        longitude,
        // Real coordinates from the source's own occurrence record, not
        // inferred from the neighbourhood — same standard as PRF.
        geoPrecision: "EXACT",
        locationConfidence: 1.0,
        neighborhood: bairro || undefined,
        city: (row["MUNICÍPIO(S)"] as string) ?? MUNICIPALITY,
        state: "PA",
        severity: severityFor(eventType),
        confidenceScore: 1.0,
      });
    }

    return Promise.resolve(events);
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(BASE_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on source page` };
      }
      const html = await res.text();
      if (!html.includes("csrfmiddlewaretoken")) {
        return { status: "RED", message: "Search form not found on source page — markup may have changed" };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
