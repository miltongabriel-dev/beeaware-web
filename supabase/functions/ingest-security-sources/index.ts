// BeeAware Brasil roadmap — scheduled ingestion job.
//
// Called by pg_cron (see supabase/migrations/20260821130000_security_
// intelligence_ingestion.sql) once per source at its documented cadence,
// or manually with a specific `adapter` name (or none, to run everything)
// for testing. For each adapter: healthCheck() -> upsert its
// security_sources row -> if healthy, fetch() -> persist raw_events
// (BeeAware Global blueprint Phase 0 — see persistRawEvents()) ->
// normalize() -> upsert into geo_areas (territorial adapters),
// security_events (event adapters), or travel_advisories (advisory
// adapters — BeeAware Global blueprint Phase 1 part 2; a distinct entity
// from SecurityEvent, see adapters/types.ts's TravelAdvisory comment).
//
// Honest current state: IbgeAdapter's normalize() is fully implemented,
// so its scheduled run genuinely writes geo_areas rows. PrfAccidentsAdapter,
// RjIspAdapter, PaSegupAdapter, MgAdapter (Phase 2 — Minas Gerais),
// EsSespAdapter (Phase 2 — Espírito Santo, EXACT-precision with real
// coordinates), AlAdapter (Phase 2 — Alagoas, real per-occurrence unique
// IDs) and UnodcAdapter (BeeAware Global blueprint Phase 1 — the first
// adapter that isn't Brazil-specific) are also fully real (verified
// against their live sources — see each file's header) and
// write actual security_events rows. FcdoAdapter (Phase 1 part 2) is also
// fully real and writes travel_advisories rows instead. RsSspAdapter
// (Phase 2 hardening) is real too but genuinely flaky — its source file is
// right at this Edge Function's memory ceiling (~12.5% real-mode success
// per attempt, measured), so it's scheduled daily rather than monthly and
// leans on idempotent upserts to retry safely (see
// rs_ssp_cron_daily.sql's comment). SinespAdapter's parsing logic is now
// genuinely real too (a real bulk-download URL was found — not the
// dados.gov.br REST API, whose every listed resource points at a dead
// domain, but a file hosted directly on gov.br, found via web search —
// and real per-occurrence-cell parsing verified locally against the
// actual file), but it is NOT REGISTERED below: fetch() has failed 3/3
// real attempts in production. See sinesp.ts's own header for the full
// diagnosis, including a likely shared root cause with SpVehicleAdapter
// (also built, also not registered, see sp_vehicle.ts). RenaestAdapter
// still has working fetch() (real discovery against its live source) but
// normalize() returns [] (see the adapter's file header for why) — so
// its scheduled runs today only keep security_sources health metadata
// current. That's not nothing (it's exactly what the roadmap's source-
// health dashboard, section 12.5, is meant to show), but it's not event
// data yet either.

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { IbgeAdapter } from "../_shared/adapters/br/ibge.ts";
// SinespAdapter (sinesp.ts) is built and correct — real bulk-download URL
// found, real parsing verified locally against the actual file — but not
// registered. fetch() has never completed in production despite three
// rounds of mitigation (default region, sa-east-1 pinning, chunked
// downloading); see the file's own header for the full diagnostic trail
// and why the remaining bottleneck looks like the origin server's own
// fixed overhead rather than anything fixable from this project's side.
// import { SinespAdapter } from "../_shared/adapters/br/sinesp.ts";
import { RenaestAdapter } from "../_shared/adapters/br/renaest.ts";
import { PrfAccidentsAdapter } from "../_shared/adapters/br/prf.ts";
import { RjIspAdapter } from "../_shared/adapters/br/rj_isp.ts";
import { PaSegupAdapter } from "../_shared/adapters/br/pa_segup.ts";
import { MgAdapter } from "../_shared/adapters/br/mg_ssp.ts";
import { EsSespAdapter } from "../_shared/adapters/br/es_sesp.ts";
import { AlAdapter } from "../_shared/adapters/br/al_seds.ts";
// BaAdapter (ba_ssp.ts) is built and correct but not registered — the
// source server's TLS certificate chain is genuinely broken, see the
// file's own header for the openssl-verified detail.
import { UnodcAdapter } from "../_shared/adapters/global/unodc.ts";
import { FcdoAdapter } from "../_shared/adapters/global/fcdo_travel_advisory.ts";
import { RsSspAdapter } from "../_shared/adapters/br/rs_ssp.ts";
// SpVehicleAdapter (sp_vehicle.ts) is built and correct but not
// registered — every real attempt (default region, sa-east-1, chunked
// downloading) has failed fast (~2-4s), a different and still-unexplained
// shape of failure from SinespAdapter's (likely a connection-level
// rejection rather than a resource/timing limit — see the file's own
// header).
// import { SpVehicleAdapter } from "../_shared/adapters/br/sp_vehicle.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
  TerritorialSourceAdapter,
  TravelAdvisory,
  TravelAdvisoryAdapter,
} from "../_shared/adapters/types.ts";

const territorialAdapters: Record<string, TerritorialSourceAdapter> = {
  IbgeAdapter: new IbgeAdapter(),
};

const advisoryAdapters: Record<string, TravelAdvisoryAdapter> = {
  FcdoAdapter: new FcdoAdapter(),
};

const eventAdapters: Record<string, SecuritySourceAdapter> = {
  RenaestAdapter: new RenaestAdapter(),
  PrfAccidentsAdapter: new PrfAccidentsAdapter(),
  RjIspAdapter: new RjIspAdapter(),
  PaSegupAdapter: new PaSegupAdapter(),
  MgAdapter: new MgAdapter(),
  EsSespAdapter: new EsSespAdapter(),
  AlAdapter: new AlAdapter(),
  UnodcAdapter: new UnodcAdapter(),
  RsSspAdapter: new RsSspAdapter(),
};

async function upsertSourceRegistry(
  supabase: SupabaseClient,
  source: SecuritySource,
  health: SourceHealth,
): Promise<string | null> {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from("security_sources")
    .upsert(
      {
        country_code: source.countryCode,
        state_code: source.stateCode ?? null,
        name: source.name,
        organisation: source.organisation ?? null,
        source_type: source.sourceType,
        source_url: source.sourceUrl ?? null,
        adapter_name: source.adapterName,
        adapter_version: source.adapterVersion,
        refresh_frequency: source.refreshFrequency ?? null,
        last_check: now,
        ...(health.status !== "RED" ? { last_success: now } : {}),
        last_data_date: health.lastDataDate ?? null,
        active: true,
      },
      { onConflict: "adapter_name" },
    )
    .select("id")
    .single();

  if (error) {
    console.error(`security_sources upsert failed for ${source.adapterName}:`, error.message);
    return null;
  }
  return data?.id ?? null;
}

// BeeAware Global blueprint — raw_events (Phase 0). Every adapter's
// fetch() already returns this same RawSecurityRecord[] shape, so this
// persists replay-capable raw payloads for any adapter with zero changes
// to the adapter files themselves. payload is bytea, sent as Postgres's
// standard `\x`-prefixed hex text (PostgREST casts a hex-prefixed string
// to bytea on insert) — chosen over base64 because it's the format
// Postgres itself uses natively, not a workaround.
function toBytes(payload: unknown): Uint8Array {
  if (payload instanceof Uint8Array) return payload;
  const text = typeof payload === "string" ? payload : JSON.stringify(payload);
  return new TextEncoder().encode(text);
}

// Genuinely necessary, not just tidy: Array.from(bytes, fn).join("") — a
// reasonable-looking first attempt — hit WORKER_RESOURCE_LIMIT on
// RjIspAdapter's ~7MB raw CSV text payload. Millions of individual
// 2-character string objects (one per byte) plus the array holding them
// is a large multiple of the input size in V8, not the ~2x hex encoding
// itself implies. This writes straight into one pre-sized byte buffer
// (ASCII hex digits are valid UTF-8) and decodes it once — no
// intermediate per-byte allocations.
const HEX_DIGITS = "0123456789abcdef";

function toHex(bytes: Uint8Array): string {
  const hexBytes = new Uint8Array(bytes.length * 2);
  for (let i = 0; i < bytes.length; i++) {
    const byte = bytes[i];
    hexBytes[i * 2] = HEX_DIGITS.charCodeAt(byte >> 4);
    hexBytes[i * 2 + 1] = HEX_DIGITS.charCodeAt(byte & 0x0f);
  }
  return new TextDecoder().decode(hexBytes);
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return toHex(new Uint8Array(digest));
}

async function persistRawEvents(
  supabase: SupabaseClient,
  sourceId: string | null,
  adapterName: string,
  records: RawSecurityRecord[],
): Promise<void> {
  if (records.length === 0) return;

  // toHex() itself is cheap (linear, pre-sized buffer — see its own
  // comment), but for a genuinely large payload the hex string it
  // produces (2x the input) plus the original bytes plus whatever the
  // adapter's own normalize() needs concurrently (RsSspAdapter's 95MB
  // decompressed CSV, streamed but still substantial) can combine to
  // cross the Edge Function's memory budget — confirmed live: RsSspAdapter
  // debug mode, which worked before raw_events existed, started hitting
  // WORKER_RESOURCE_LIMIT once persistRawEvents ran unconditionally ahead
  // of it. Every other adapter's payload measured well under this
  // (RjIspAdapter's ~7MB text was the previous largest, confirmed working)
  // — skip raw persistence above that, rather than lower the bar for
  // everyone. The source file itself stays downloadable from SSP-RS's own
  // site if a raw copy is ever needed, unlike a live API response.
  const RAW_PAYLOAD_SIZE_LIMIT = 8_000_000;

  const rows = (
    await Promise.all(
      records.map(async (record) => {
        const bytes = toBytes(record.payload);
        if (bytes.length > RAW_PAYLOAD_SIZE_LIMIT) {
          console.warn(
            `raw_events: skipping ${adapterName}/${record.sourceRecordId} — ${bytes.length} bytes exceeds the ${RAW_PAYLOAD_SIZE_LIMIT}-byte raw-persistence limit`,
          );
          return null;
        }
        return {
          source_id: sourceId,
          source_record_id: record.sourceRecordId,
          payload: `\\x${toHex(bytes)}`,
          checksum: await sha256Hex(bytes),
          adapter_name: adapterName,
        };
      }),
    )
  ).filter((row) => row !== null);

  if (rows.length === 0) return;

  const { error } = await supabase.from("raw_events").insert(rows);
  if (error) console.error(`raw_events insert failed for ${adapterName}:`, error.message);
}

async function runTerritorialAdapter(supabase: SupabaseClient, adapter: TerritorialSourceAdapter) {
  const source = adapter.source();
  const health = await adapter.healthCheck();
  const sourceId = await upsertSourceRegistry(supabase, source, health);

  if (health.status === "RED") {
    return { adapter: source.adapterName, health, areasWritten: 0 };
  }

  const records = await adapter.fetch();
  await persistRawEvents(supabase, sourceId, source.adapterName, records);
  let written = 0;
  for (const record of records) {
    const areas = await adapter.normalize(record);
    for (const area of areas) {
      const { error } = await supabase.from("geo_areas").upsert(
        {
          country_code: area.countryCode,
          state_code: area.stateCode ?? null,
          city_ibge_code: area.cityIbgeCode ?? null,
          area_type: area.areaType,
          name: area.name,
          geometry: area.geometry ?? null,
          source: area.source,
          source_version: area.sourceVersion ?? null,
        },
        { onConflict: "country_code,state_code,city_ibge_code,area_type" },
      );
      if (!error) written++;
      else console.error(`geo_areas upsert failed for ${area.name}:`, error.message);
    }
  }

  return { adapter: source.adapterName, health, recordsSeen: records.length, areasWritten: written };
}

function mapAdvisoryToRow(sourceId: string | null, advisory: TravelAdvisory) {
  return {
    source_id: sourceId,
    country_code: advisory.countryCode,
    country_slug: advisory.countrySlug,
    issuer: advisory.issuer,
    level: advisory.level,
    raw_alert_status: advisory.rawAlertStatus,
    summary: advisory.summary ?? null,
    source_url: advisory.sourceUrl ?? null,
    effective_at: advisory.effectiveAt ?? null,
  };
}

async function runAdvisoryAdapter(supabase: SupabaseClient, adapter: TravelAdvisoryAdapter, debug = false) {
  const source = adapter.source();
  const health = await adapter.healthCheck();
  const sourceId = await upsertSourceRegistry(supabase, source, health);

  if (health.status === "RED") {
    return { adapter: source.adapterName, health, advisoriesWritten: 0 };
  }

  const records = await adapter.fetch();
  await persistRawEvents(supabase, sourceId, source.adapterName, records);

  if (debug) {
    const normalized: TravelAdvisory[] = [];
    for (const record of records) {
      normalized.push(...(await adapter.normalize(record)));
    }
    return {
      adapter: source.adapterName,
      health,
      recordsSeen: records.length,
      advisoriesNormalized: normalized.length,
      sample: normalized.slice(0, 3),
    };
  }

  let written = 0;
  const rows: ReturnType<typeof mapAdvisoryToRow>[] = [];
  for (const record of records) {
    const advisories = await adapter.normalize(record);
    for (const advisory of advisories) rows.push(mapAdvisoryToRow(sourceId, advisory));
  }

  for (let i = 0; i < rows.length; i += EVENT_BATCH_SIZE) {
    const batch = rows.slice(i, i + EVENT_BATCH_SIZE);
    const { error } = await supabase
      .from("travel_advisories")
      .upsert(batch, { onConflict: "source_id,country_code" });
    if (!error) written += batch.length;
    else console.error(`travel_advisories batch upsert failed (rows ${i}-${i + batch.length}):`, error.message);
  }

  return { adapter: source.adapterName, health, recordsSeen: records.length, advisoriesWritten: written };
}

// Not yet exercised against real rows — SinespAdapter/RenaestAdapter/
// PrfAccidentsAdapter's normalize() all return [] today (see their file
// headers), so this never actually runs with real data yet. Written for
// when normalize() is filled in, using EWKT text for the point geometry
// (PostgREST/PostGIS accept `SRID=4326;POINT(lng lat)` on a geometry
// column) — worth a real insert test once there's an event to insert.
function mapEventToRow(sourceId: string | null, event: SecurityEvent) {
  return {
    country_code: event.countryCode,
    state_code: event.stateCode ?? null,
    city_ibge_code: event.cityIbgeCode ?? null,
    source_id: sourceId,
    source_record_id: event.sourceRecordId,
    source_type: event.sourceType,
    event_category: event.eventCategory,
    event_type: event.eventType,
    event_subtype: event.eventSubtype ?? null,
    original_category: event.originalCategory ?? null,
    occurred_at: event.occurredAt ?? null,
    reported_at: event.reportedAt ?? null,
    published_at: event.publishedAt ?? null,
    location:
      event.latitude != null && event.longitude != null
        ? `SRID=4326;POINT(${event.longitude} ${event.latitude})`
        : null,
    geo_precision: event.geoPrecision,
    location_confidence: event.locationConfidence ?? null,
    neighborhood: event.neighborhood ?? null,
    district: event.district ?? null,
    city: event.city ?? null,
    state: event.state ?? null,
    occurrence_count: event.occurrenceCount ?? 1,
    victim_count: event.victimCount ?? null,
    severity: event.severity ?? null,
    confidence_score: event.confidenceScore ?? null,
    raw_payload: event.rawPayload ?? null,
  };
}

// PRF's single "grouped by occurrence" file already carries ~34k rows for
// the current year alone — one upsert call per row (as this used to do)
// means ~34k sequential round trips to PostgREST, which is both slow and
// a real risk of running past the Edge Function's execution limit. Batch
// instead: PostgREST/supabase-js upsert() accepts an array and turns it
// into one bulk statement, so this is ~34k/EVENT_BATCH_SIZE calls.
const EVENT_BATCH_SIZE = 500;

async function runEventAdapter(supabase: SupabaseClient, adapter: SecuritySourceAdapter, debug = false) {
  const source = adapter.source();
  const health = await adapter.healthCheck();
  const sourceId = await upsertSourceRegistry(supabase, source, health);

  if (health.status === "RED") {
    return { adapter: source.adapterName, health, eventsWritten: 0 };
  }

  const records = await adapter.fetch();
  await persistRawEvents(supabase, sourceId, source.adapterName, records);
  // debug:true runs fetch() + normalize() but skips the DB write, and
  // returns a small sample instead of every event (a full binary
  // payload or tens of thousands of rows echoed as JSON is its own way
  // to blow the response size/memory budget) — for inspecting what an
  // adapter actually produces without needing a separate script or DB
  // access.
  if (debug) {
    const normalized: SecurityEvent[] = [];
    for (const record of records) {
      normalized.push(...(await adapter.normalize(record)));
    }
    return {
      adapter: source.adapterName,
      health,
      recordsSeen: records.length,
      eventsNormalized: normalized.length,
      sample: normalized.slice(0, 3),
    };
  }
  let written = 0;
  for (const record of records) {
    const events = await adapter.normalize(record);

    // Postgres rejects an entire multi-row upsert with "ON CONFLICT DO
    // UPDATE command cannot affect row a second time" the moment two rows
    // in the SAME statement share a conflict key — found in production
    // with PaSegupAdapter, whose sourceRecordId is a composite fingerprint
    // (no real unique ID in the source data) with a documented small
    // collision rate. Two colliding rows landing in the same batch was
    // silently failing that whole 500-row batch (only the last, smaller
    // batch without a collision got through). Dedupe by key before
    // batching so this can't happen for any adapter, not just this one.
    // Built directly from `events` (skipping a separate intermediate
    // `rows` array) since RsSspAdapter's row count made every extra
    // full-array copy here matter — see its file header for the memory
    // budget this ingestion job runs under.
    const bySourceRecordId = new Map<string, ReturnType<typeof mapEventToRow>>();
    for (const event of events) {
      bySourceRecordId.set(event.sourceRecordId, mapEventToRow(sourceId, event));
    }
    const dedupedRows = [...bySourceRecordId.values()];

    for (let i = 0; i < dedupedRows.length; i += EVENT_BATCH_SIZE) {
      const batch = dedupedRows.slice(i, i + EVENT_BATCH_SIZE);
      const { error } = await supabase
        .from("security_events")
        .upsert(batch, { onConflict: "source_id,source_record_id" });
      if (!error) written += batch.length;
      else console.error(`security_events batch upsert failed (rows ${i}-${i + batch.length}):`, error.message);
    }
  }

  return { adapter: source.adapterName, health, recordsSeen: records.length, eventsWritten: written };
}

// One-off (not cron-scheduled) backfill: populates geometry on the
// municipality geo_areas rows IbgeAdapter's regular sync already created
// (identity only, geometry left null — see ibge.ts). Triggered manually
// with {"action": "backfill-geometry", "stateCode": "RJ"} rather than
// running for every state automatically, since it's only needed where a
// choropleth actually consumes it (RJ today, for RjIspAdapter).
async function backfillGeometry(supabase: SupabaseClient, stateCode: string) {
  const ibge = new IbgeAdapter();
  const rows = await ibge.fetchAndNormalizeGeometry(stateCode);

  let written = 0;
  for (const row of rows) {
    const { error } = await supabase
      .from("geo_areas")
      .update({ geometry: row.geometry, source_version: row.sourceVersion })
      .eq("city_ibge_code", row.cityIbgeCode)
      .eq("area_type", "MUNICIPALITY");
    if (!error) written++;
    else console.error(`geo_areas geometry update failed for ${row.cityIbgeCode}:`, error.message);
  }

  return { stateCode, municipalitiesSeen: rows.length, geometryWritten: written };
}

// One-off (not cron-scheduled) backfill: populates geo_areas.population
// (Safety Pulse / Historical Safety, roadmap Phase 5) via IBGE's SIDRA
// aggregates. Same shape as backfillGeometry above, but loops all 27 UFs
// when stateCode is omitted — unlike geometry (only needed where a
// choropleth already consumes it), Historical Safety needs population
// everywhere security_events has data, and 27 lightweight JSON calls
// comfortably fits one invocation. Triggered with
// {"action": "backfill-population"} (all UFs) or
// {"action": "backfill-population", "stateCode": "RJ"} (one).
const ALL_UF_CODES = [
  "RO", "AC", "AM", "RR", "PA", "AP", "TO",
  "MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA",
  "MG", "ES", "RJ", "SP",
  "PR", "SC", "RS",
  "MS", "MT", "GO", "DF",
];

async function backfillPopulation(supabase: SupabaseClient, stateCode?: string) {
  const ibge = new IbgeAdapter();
  const stateCodes = stateCode ? [stateCode] : ALL_UF_CODES;

  // One bulk_update_population() RPC call per state (27 total for a
  // national run), not one .update() per municipality — an earlier
  // version did exactly that (~5570 sequential round trips for a
  // national run) and hit WORKER_RESOURCE_LIMIT for real, the same
  // "one round trip per row" problem this project already fixed for
  // PRF's events (see EVENT_BATCH_SIZE above). bulk_update_population
  // does the whole state's worth of rows in one UPDATE...FROM statement.
  let municipalitiesSeen = 0;
  let populationWritten = 0;
  for (const uf of stateCodes) {
    const rows = await ibge.fetchAndNormalizePopulation(uf);
    municipalitiesSeen += rows.length;
    if (rows.length === 0) continue;

    const { data, error } = await supabase.rpc("bulk_update_population", {
      updates: rows.map((r) => ({ city_ibge_code: r.cityIbgeCode, population: r.population })),
    });
    if (!error) populationWritten += (data as number) ?? 0;
    else console.error(`bulk_update_population failed for ${uf}:`, error.message);
  }

  return { stateCodes, municipalitiesSeen, populationWritten };
}

Deno.serve(async (req) => {
  // This runs real external HTTP fetches and DB writes on every call —
  // it must only be triggerable by pg_cron (via Vault, see the
  // use-vault-for-cron-auth migration) or a trusted manual invocation with
  // that same token, never by an arbitrary request.
  //
  // Deliberately NOT compared against Deno.env SUPABASE_SERVICE_ROLE_KEY:
  // on this project that reserved env var holds a stale value that no
  // longer matches the project's current legacy service_role key (verified
  // by hand — same sha256 mismatch against `supabase secrets list`'s
  // digest — and Supabase doesn't let user code refresh it, `secrets set
  // SUPABASE_SERVICE_ROLE_KEY=...` is rejected as a reserved name). A
  // dedicated secret we set ourselves avoids depending on that.
  const auth = req.headers.get("Authorization") ?? "";
  const authToken = Deno.env.get("INGEST_FUNCTION_AUTH_TOKEN");
  if (!authToken || auth !== `Bearer ${authToken}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, serviceRoleKey);

  let body: { adapter?: string; action?: string; stateCode?: string; debug?: boolean } = {};
  try {
    body = await req.json();
  } catch {
    // No body / not JSON -> run every adapter.
  }

  if (body.action === "backfill-geometry") {
    if (!body.stateCode) {
      return new Response(JSON.stringify({ ok: false, error: "stateCode required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }
    const result = await backfillGeometry(supabase, body.stateCode);
    return new Response(JSON.stringify({ ok: true, result }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  if (body.action === "backfill-population") {
    const result = await backfillPopulation(supabase, body.stateCode);
    return new Response(JSON.stringify({ ok: true, result }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const results: Record<string, unknown> = {};

  for (const [name, adapter] of Object.entries(territorialAdapters)) {
    if (body.adapter && body.adapter !== name) continue;
    results[name] = await runTerritorialAdapter(supabase, adapter);
  }

  for (const [name, adapter] of Object.entries(eventAdapters)) {
    if (body.adapter && body.adapter !== name) continue;
    results[name] = await runEventAdapter(supabase, adapter, body.debug === true);
  }

  for (const [name, adapter] of Object.entries(advisoryAdapters)) {
    if (body.adapter && body.adapter !== name) continue;
    results[name] = await runAdvisoryAdapter(supabase, adapter, body.debug === true);
  }

  return new Response(JSON.stringify({ ok: true, results }), {
    headers: { "Content-Type": "application/json" },
  });
});
