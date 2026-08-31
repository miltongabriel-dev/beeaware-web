-- BeeAware Global roadmap — UK Police Force-level crime summary.
--
-- Same shape as cisp_crime_summary (20260825270000) — one tier coarser
-- (43 England & Wales police forces instead of RJ's ~137 CISPs), now that
-- UkPoliceAdapter emits DISTRICT-precision events with a real
-- geo_area_id (via the security_events_resolve_geo_area trigger, widened
-- for 'POLICE_FORCE' by 20260831130000). Keyed generically by
-- geo_area_id/area_type='POLICE_FORCE' rather than hardcoding GB, same
-- reasoning as cisp_crime_summary's own header.
create function police_force_crime_summary(months_back integer default 3)
returns table (
  force_area_id uuid,
  force_name text,
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
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'PUBLIC_SAFETY'), 0) as public_safety_count,
    coalesce(sum(se.occurrence_count), 0) as total_count
  from geo_areas ga
  join security_events se on se.geo_area_id = ga.id
  where ga.area_type = 'POLICE_FORCE'
    and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY')
    and se.occurred_at >= (now() - (months_back || ' months')::interval)
  group by ga.id, ga.name, ga.country_code, ga.geometry;
$$;

grant execute on function police_force_crime_summary(integer) to anon, authenticated;
