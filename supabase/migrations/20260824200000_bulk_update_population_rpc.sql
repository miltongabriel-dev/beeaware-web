-- BeeAware Brasil roadmap / Phase 5 — Safety Pulse, bulk population
-- update helper.
--
-- The first backfill-population run did one .update() call per
-- municipality from the Edge Function (~5570 sequential PostgREST round
-- trips for a national run) — the exact same "one round trip per row"
-- problem this project already hit and fixed for PRF's ~34k events
-- (index.ts's EVENT_BATCH_SIZE comment). A plain upsert can't batch this
-- instead: geo_areas.name is NOT NULL, and Postgres validates NOT NULL
-- on the incoming row before ON CONFLICT resolution even runs, so an
-- upsert payload with only city_ibge_code/population would fail even
-- though every row already exists and only an UPDATE is ever intended.
-- A single UPDATE...FROM a jsonb array does the whole state in one
-- database round trip instead.
create or replace function bulk_update_population(updates jsonb)
returns integer
language plpgsql
as $$
declare
  updated_count integer;
begin
  update geo_areas ga
  set population = (u.value->>'population')::integer
  from jsonb_array_elements(updates) u
  where ga.city_ibge_code = u.value->>'city_ibge_code'
    and ga.area_type = 'MUNICIPALITY';
  get diagnostics updated_count = row_count;
  return updated_count;
end;
$$;
