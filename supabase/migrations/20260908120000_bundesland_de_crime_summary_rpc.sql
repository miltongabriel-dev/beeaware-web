-- BeeAware Global roadmap — bundesland_de_crime_summary, Germany's
-- state-level choropleth RPC. Same shape as departement_fr_crime_summary/
-- municipio_es_crime_summary/concelho_crime_summary/police_force_crime_summary/
-- lgd_crime_summary.
--
-- Starts directly with `group by ga.id` (not the fuller tuple) — same
-- proven fix already applied from the start for France, after concelho_
-- crime_summary and municipio_es_crime_summary both timed out under
-- concurrent load with the fuller group-by and needed a follow-up fix
-- migration each time.
--
-- DeCrimeAdapter's leftover "Sachbeschädigung" (property damage that
-- isn't theft — see that adapter's header) is tagged COMMUNITY, folded
-- into public_safety_count here — same fold-in every other country's
-- own leftover category already gets (France's "Destructions et
-- dégradations volontaires", Spain's "resto convencional", Portugal's
-- ROAD_SAFETY).
--
-- months_back defaults to 24, not 12: BKA's PKS publishes a closed
-- annual year with real publication lag (2025 data only became
-- available in March 2026) — same reasoning as concelho_crime_summary/
-- departement_fr_crime_summary.
create function bundesland_de_crime_summary(months_back integer default 24)
returns table (
  bundesland_id uuid,
  bundesland_name text,
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
  where ga.area_type = 'BUNDESLAND'
    and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY', 'COMMUNITY')
    and se.occurred_at >= (now() - (months_back || ' months')::interval)
  group by ga.id;
$$;

grant execute on function bundesland_de_crime_summary(integer) to anon, authenticated;
