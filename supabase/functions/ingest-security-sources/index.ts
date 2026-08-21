// BeeAware Brasil roadmap — scheduled ingestion job.
//
// Called by pg_cron (see supabase/migrations/20260821130000_security_
// intelligence_ingestion.sql) once per source at its documented cadence,
// or manually with a specific `adapter` name (or none, to run everything)
// for testing. For each adapter: healthCheck() -> upsert its
// security_sources row -> if healthy, fetch() -> normalize() -> upsert
// into geo_areas (territorial adapters) or security_events (event
// adapters).
//
// Honest current state: IbgeAdapter's normalize() is fully implemented,
// so its scheduled run genuinely writes geo_areas rows. PrfAccidentsAdapter
// and RjIspAdapter are also fully real (verified against their live
// sources — see each file's header) and write actual security_events
// rows. SinespAdapter and RenaestAdapter still have working fetch() (real
// discovery against their live sources) but normalize() returns [] (see
// each adapter's file header for why) — so their scheduled runs today
// only keep security_sources health metadata current. That's not nothing
// (it's exactly what the roadmap's source-health dashboard, section 12.5,
// is meant to show), but it's not event data yet either.

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { IbgeAdapter } from "../_shared/adapters/br/ibge.ts";
import { SinespAdapter } from "../_shared/adapters/br/sinesp.ts";
import { RenaestAdapter } from "../_shared/adapters/br/renaest.ts";
import { PrfAccidentsAdapter } from "../_shared/adapters/br/prf.ts";
import { RjIspAdapter } from "../_shared/adapters/br/rj_isp.ts";
import { PaSegupAdapter } from "../_shared/adapters/br/pa_segup.ts";
// RsSspAdapter (rs_ssp.ts) is built and its fetch()/normalize() are
// verified working in production, but not imported/registered here yet
// — see the eventAdapters comment below for why.
import type {
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
  TerritorialSourceAdapter,
} from "../_shared/adapters/types.ts";

const territorialAdapters: Record<string, TerritorialSourceAdapter> = {
  IbgeAdapter: new IbgeAdapter(),
};

const eventAdapters: Record<string, SecuritySourceAdapter> = {
  SinespAdapter: new SinespAdapter(),
  RenaestAdapter: new RenaestAdapter(),
  PrfAccidentsAdapter: new PrfAccidentsAdapter(),
  RjIspAdapter: new RjIspAdapter(),
  PaSegupAdapter: new PaSegupAdapter(),
  // RsSspAdapter is deliberately NOT registered here yet. fetch()/
  // normalize() both work (verified live: 23741 real aggregate events,
  // ~123MB RSS — see rs_ssp.ts's file header) but the write phase
  // (~160 sequential batch upserts for that many rows) still hits
  // WORKER_RESOURCE_LIMIT in production, for reasons not yet isolated
  // (probably cumulative memory/time held across that many sequential
  // round trips, not peak memory the way the parse-phase failure was).
  // Registering it here would mean a manual "run every adapter" call or
  // the eventual scheduled job breaks on this one adapter. Paused,
  // not abandoned — re-add (uncomment the import above too) once the
  // write path is fixed (either a scope reduction like PaSegupAdapter's,
  // or real incremental writes spread across multiple scheduled runs).
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

async function runTerritorialAdapter(supabase: SupabaseClient, adapter: TerritorialSourceAdapter) {
  const source = adapter.source();
  const health = await adapter.healthCheck();
  await upsertSourceRegistry(supabase, source, health);

  if (health.status === "RED") {
    return { adapter: source.adapterName, health, areasWritten: 0 };
  }

  const records = await adapter.fetch();
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

  const results: Record<string, unknown> = {};

  for (const [name, adapter] of Object.entries(territorialAdapters)) {
    if (body.adapter && body.adapter !== name) continue;
    results[name] = await runTerritorialAdapter(supabase, adapter);
  }

  for (const [name, adapter] of Object.entries(eventAdapters)) {
    if (body.adapter && body.adapter !== name) continue;
    results[name] = await runEventAdapter(supabase, adapter, body.debug === true);
  }

  return new Response(JSON.stringify({ ok: true, results }), {
    headers: { "Content-Type": "application/json" },
  });
});
