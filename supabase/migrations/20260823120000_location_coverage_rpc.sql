-- BeeAware Global blueprint — Phase 1: coverage endpoint.
--
-- Blueprint §9's GET /v1/sources/coverage?lat=&lon= ("available layers,
-- grade, freshness, geo resolution"), built as a SQL RPC rather than a
-- new Edge Function/API layer — matches how nearby_security_events and
-- municipality_crime_summary already expose read APIs directly via
-- PostgREST; there's no BFF/versioned-API layer yet, and building one is
-- its own decision (blueprint §13 still lists provider choices as open),
-- not something to fold into this endpoint.
--
-- Two genuinely different query shapes get unioned, not one: point-
-- precision/aggregate rows (EXACT through STATE) have a real `location`
-- and are found via the same ST_DWithin pattern nearby_security_events
-- already uses; UnodcAdapter's COUNTRY-level rows have no coordinate at
-- all (a national statistic isn't "near" any point) and are matched by
-- country_code instead. p_country_code is a parameter rather than
-- derived by point-in-polygon lookup — no country boundary geometry is
-- ingested yet, and the Flutter client already has a cheap country
-- guess (_preferredCountryCode() in home_screen.dart) it can pass
-- through once this is wired up client-side.
--
-- `grade` mirrors the blueprint's §6.2 table (A+/A/B/C/D/U) collapsed
-- onto what this schema actually has today (no news/community layer in
-- security_events yet, no modelled/inferred signal) — a coarse,
-- adjustable mapping from geo_precision, not a cited standard.
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

grant execute on function location_coverage(double precision, double precision, double precision, text)
  to anon, authenticated;
