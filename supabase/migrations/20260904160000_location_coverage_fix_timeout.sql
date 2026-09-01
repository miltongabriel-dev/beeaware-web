-- BeeAware Global blueprint — fix location_coverage timing out under
-- concurrent load.
--
-- Root-caused live (2026-09-01), same investigation session as the
-- choropleth RPC fixes (20260904110000-130000): confirmed via
-- HomeScreen's real cold-boot fetches (LocationCoverageApi.fetchCoverage
-- fires alongside the 4 country choropleths, all concurrently) that this
-- RPC hits "canceling statement due to statement timeout" under that
-- same real load.
--
-- The cause here is different from the choropleth RPCs' GROUP BY issue:
-- this query casts `location` (indexed as a plain geometry GIST index,
-- security_events_location_idx) to `::geography` before calling
-- ST_DWithin. That cast means the existing geometry index can't be used
-- to narrow candidate rows at all — Postgres has no choice but to
-- geography-cast and distance-check EVERY row with a non-null location
-- across the whole security_events table before it can discard the ones
-- outside radius_meters. Under concurrent load (four other heavy queries
-- competing for the same connection pool/CPU) that full scan is what
-- tips over the timeout.
--
-- Fix: add a cheap bounding-box prefilter using the untouched geometry
-- column (`location && ST_Expand(...)`), which DOES use the existing
-- GIST index, before the exact (and still necessary, for a true circular
-- radius rather than a bounding box) ST_DWithin/geography check runs —
-- the standard PostGIS "indexed bbox prefilter + exact recheck" pattern.
-- 111320.0 is metres per degree of longitude at the equator — a rough
-- but deliberately generous conversion (the prefilter only needs to be a
-- superset of the real radius, never a stricter subset, since the exact
-- ST_DWithin check still enforces the true radius afterward).
create or replace function location_coverage(
  center_lat double precision,
  center_lng double precision,
  radius_meters double precision default 15000,
  p_country_code text default null
)
returns table (
  geo_precision geo_precision,
  event_category security_event_category,
  grade text,
  source_count bigint,
  last_data_date date,
  freshness_days integer
)
language sql
stable
as $$
  select
    geo_precision,
    event_category,
    case geo_precision
      when 'EXACT' then 'A+'
      when 'STREET' then 'A+'
      when 'NEIGHBORHOOD' then 'A'
      when 'DISTRICT' then 'A'
      when 'MUNICIPALITY' then 'A'
      when 'STATE' then 'B'
      when 'COUNTRY' then 'C'
    end as grade,
    count(*) as source_count,
    max(occurred_at)::date as last_data_date,
    (current_date - max(occurred_at)::date) as freshness_days
  from security_events
  where location is not null
    and location && ST_Expand(
      ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326),
      radius_meters / 111320.0
    )
    and ST_DWithin(
      location::geography,
      ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography,
      radius_meters
    )
  group by geo_precision, event_category

  union all

  select
    geo_precision,
    event_category,
    'C' as grade,
    count(*) as source_count,
    max(occurred_at)::date as last_data_date,
    (current_date - max(occurred_at)::date) as freshness_days
  from security_events
  where location is null
    and geo_precision = 'COUNTRY'
    and p_country_code is not null
    and country_code = p_country_code
  group by geo_precision, event_category;
$$;
