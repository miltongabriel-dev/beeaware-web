-- BeeAware Brasil roadmap / Phase 4 — CISP-level crime summary.
--
-- Same shape as municipality_crime_summary (20260824160000/
-- 20260825120000), one tier finer: per police district (CISP) instead
-- of per municipality, now that RjIspAdapter emits DISTRICT-precision
-- events with a real geo_area_id (via the security_events_resolve_geo_area
-- trigger, 20260825250000) instead of aggregating straight up to
-- MUNICIPALITY. RJ-only today — no other state adapter has sub-
-- municipality geometry to join against yet — but keyed generically by
-- geo_area_id/area_type='CISP' rather than hardcoding RJ, so a future
-- state with the same CISP-equivalent granularity needs no schema
-- change here, only its own geometry migration.
--
-- 3-month default window, same reasoning as municipality_crime_summary's
-- own revert (20260825120000): a wider window risks the same statement-
-- timeout class of bug on a security_events table that's already grown
-- to 135k+ rows, and this is meant as a "recent regional picture" view,
-- not a long-window historical one (that's what Historical Safety is
-- for, at the municipality tier).
create function cisp_crime_summary(months_back integer default 3)
returns table (
  cisp_area_id uuid,
  cisp_name text,
  state_code text,
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
    ga.state_code,
    ga.geometry,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'VIOLENCE'), 0) as violence_count,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'PROPERTY'), 0) as property_count,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'PUBLIC_SAFETY'), 0) as public_safety_count,
    coalesce(sum(se.occurrence_count), 0) as total_count
  from geo_areas ga
  join security_events se on se.geo_area_id = ga.id
  where ga.area_type = 'CISP'
    and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY')
    and se.occurred_at >= (now() - (months_back || ' months')::interval)
  group by ga.id, ga.name, ga.state_code, ga.geometry;
$$;

grant execute on function cisp_crime_summary(integer) to anon, authenticated;

-- Supports this RPC's join (geo_area_id -> geo_areas) at the volume
-- security_events has grown to, same reasoning as
-- 20260825170000_security_events_municipality_join_index.sql.
create index security_events_geo_area_occurred_idx
  on security_events (geo_area_id, occurred_at)
  where geo_area_id is not null;
