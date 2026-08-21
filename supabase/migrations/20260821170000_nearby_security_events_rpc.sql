-- BeeAware Brasil roadmap — map consumption layer, step 1: a bounded
-- read RPC for security_events.
--
-- The app already has a "fetch official incidents for the visible map
-- area" pattern (UkPoliceApi.fetchForArea -> IncidentStore.
-- syncOfficialForBounds, called on every map move) — this RPC is the
-- Brazil-side equivalent data source for it. ST_DWithin on the geography
-- cast uses the existing security_events_location_idx (GIST) index, so
-- this stays fast even as more sources add rows.
--
-- Deliberately excludes rows with a null `location`: geo_precision
-- coarser than a real point (e.g. IBGE's municipality-level geo_areas,
-- which aren't security_events at all, or any future source that only
-- has city/state-level confidence) must never be rendered as an exact
-- map pin — the roadmap's geographic-honesty rule (section 7.2).
create or replace function nearby_security_events(
  center_lat double precision,
  center_lng double precision,
  radius_meters double precision,
  max_results integer default 300
)
returns setof security_events
language sql
stable
as $$
  select *
  from security_events
  where location is not null
    and geo_precision in ('EXACT', 'STREET')
    and ST_DWithin(
      location::geography,
      ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography,
      radius_meters
    )
  order by location::geography <-> ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography
  limit max_results;
$$;

grant execute on function nearby_security_events(double precision, double precision, double precision, integer)
  to anon, authenticated;
