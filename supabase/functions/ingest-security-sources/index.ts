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
// so its scheduled run genuinely writes geo_areas rows. SinespAdapter,
// RenaestAdapter and PrfAccidentsAdapter all have working fetch() (real
// discovery against their live sources) but normalize() still returns []
// (see each adapter's file header for why) — so their scheduled runs
// today only keep security_sources health metadata current. That's not
// nothing (it's exactly what the roadmap's source-health dashboard,
// section 12.5, is meant to show), but it's not event data yet either.

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { IbgeAdapter } from "../_shared/adapters/br/ibge.ts";
import { SinespAdapter } from "../_shared/adapters/br/sinesp.ts";
import { RenaestAdapter } from "../_shared/adapters/br/renaest.ts";
import { PrfAccidentsAdapter } from "../_shared/adapters/br/prf.ts";
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

async function runEventAdapter(supabase: SupabaseClient, adapter: SecuritySourceAdapter) {
  const source = adapter.source();
  const health = await adapter.healthCheck();
  const sourceId = await upsertSourceRegistry(supabase, source, health);

  if (health.status === "RED") {
    return { adapter: source.adapterName, health, eventsWritten: 0 };
  }

  const records = await adapter.fetch();
  let written = 0;
  for (const record of records) {
    const events = await adapter.normalize(record);
    for (const event of events) {
      const { error } = await supabase
        .from("security_events")
        .upsert(mapEventToRow(sourceId, event), { onConflict: "source_id,source_record_id" });
      if (!error) written++;
      else console.error(`security_events upsert failed for ${event.sourceRecordId}:`, error.message);
    }
  }

  return { adapter: source.adapterName, health, recordsSeen: records.length, eventsWritten: written };
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

  let body: { adapter?: string } = {};
  try {
    body = await req.json();
  } catch {
    // No body / not JSON -> run every adapter.
  }

  const results: Record<string, unknown> = {};

  for (const [name, adapter] of Object.entries(territorialAdapters)) {
    if (body.adapter && body.adapter !== name) continue;
    results[name] = await runTerritorialAdapter(supabase, adapter);
  }

  for (const [name, adapter] of Object.entries(eventAdapters)) {
    if (body.adapter && body.adapter !== name) continue;
    results[name] = await runEventAdapter(supabase, adapter);
  }

  return new Response(JSON.stringify({ ok: true, results }), {
    headers: { "Content-Type": "application/json" },
  });
});
