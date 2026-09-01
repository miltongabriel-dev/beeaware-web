-- BeeAware Global roadmap — fix concelho_crime_summary timing out under
-- concurrent load.
--
-- Root-caused live (2026-09-01): the RPC ran fine alone (306 rows, fast),
-- but timed out ("canceling statement due to statement timeout") when
-- the Flutter client fetched all four countries' choropleths at once on
-- HomeScreen.initState. Grouping by ga.geometry (a real PostGIS column,
-- up to a few KB per concelho) forces Postgres to hash/sort the full
-- geometry value per group; under concurrent load that tipped the query
-- over the statement timeout. ga.id is geo_areas' actual primary key, so
-- Postgres already treats ga.name/ga.country_code/ga.geometry as
-- functionally dependent on it — grouping by ga.id alone is valid SQL
-- here and drops the expensive geometry comparison from the group key
-- entirely. Same fix needed for municipio_es_crime_summary
-- (20260904130000) — police_force_crime_summary/municipality_crime_summary
-- aren't touched here since they weren't observed to time out.
create or replace function concelho_crime_summary(months_back integer default 24)
returns table (
  concelho_id uuid,
  concelho_name text,
  country_code text,
  geometry geometry,
  violence_count bigint,
  property_count bigint,
  public_safety_count bigint,
  total_count bigint
)
language sql
stable
as $$
  select
    ga.id,
    ga.name,
    ga.country_code,
    ga.geometry,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'VIOLENCE'), 0) as violence_count,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'PROPERTY'), 0) as property_count,
    coalesce(sum(se.occurrence_count) filter (where se.event_category in ('PUBLIC_SAFETY', 'ROAD_SAFETY')), 0) as public_safety_count,
    coalesce(sum(se.occurrence_count), 0) as total_count
  from geo_areas ga
  join security_events se on se.geo_area_id = ga.id
  where ga.area_type = 'CONCELHO'
    and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY', 'ROAD_SAFETY')
    and se.occurred_at >= (now() - (months_back || ' months')::interval)
  group by ga.id;
$$;
