-- BeeAware Global roadmap — departement_fr_crime_summary, France's
-- department-level choropleth RPC. Same shape as concelho_crime_summary/
-- municipio_es_crime_summary/police_force_crime_summary/lgd_crime_summary.
--
-- Starts directly with `group by ga.id` (not the fuller
-- ga.id, ga.name, ga.country_code, ga.geometry tuple) — concelho_crime_
-- summary and municipio_es_crime_summary both timed out under
-- concurrent load with the fuller group-by and needed a follow-up fix
-- migration each time (large-geometry PostGIS joins); grouping by the
-- primary key alone (valid since geo_areas.id is the PK, so the other
-- selected ga.* columns are functionally dependent) is the
-- already-proven fix, applied here from the start instead of waiting
-- for the same timeout to reoccur a third time.
--
-- FrCrimeAdapter's leftover "Destructions et dégradations volontaires"
-- category (see that adapter's header — no clean VIOLENCE/PROPERTY
-- bucket fits property damage that isn't theft) is tagged COMMUNITY,
-- folded into public_safety_count here so the UI keeps its usual
-- 3-colour shape — same fold-in Portugal (ROAD_SAFETY) and Spain
-- (COMMUNITY) already use for their own source's leftover category.
--
-- months_back defaults to 24, not 12: SSMSI publishes a closed annual
-- year (like Portugal's DGPJ, not Spain's year-to-date cumulative
-- balance) with real publication lag (2025 data only became available
-- in July 2026) — the window needs to be wide enough to survive the gap
-- between publication and this project's own 12-month
-- security_events retention cutoff.
create function departement_fr_crime_summary(months_back integer default 24)
returns table (
  departement_id uuid,
  departement_name text,
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
    coalesce(sum(se.occurrence_count) filter (where se.event_category in ('PUBLIC_SAFETY', 'COMMUNITY')), 0) as public_safety_count,
    coalesce(sum(se.occurrence_count), 0) as total_count
  from geo_areas ga
  join security_events se on se.geo_area_id = ga.id
  where ga.area_type = 'DEPARTEMENT'
    and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY', 'COMMUNITY')
    and se.occurred_at >= (now() - (months_back || ' months')::interval)
  group by ga.id;
$$;

grant execute on function departement_fr_crime_summary(integer) to anon, authenticated;
