-- BeeAware Global roadmap — fix municipio_es_crime_summary timing out
-- under concurrent load. Same root cause and same fix as
-- concelho_crime_summary (20260904120000) — see that migration's header
-- for the full diagnosis. Spain's geometries run larger (up to ~11.9KB
-- per municipio) than Portugal's, which is consistent with ES's version
-- of this query being the one that timed out first.
create or replace function municipio_es_crime_summary(months_back integer default 24)
returns table (
  municipio_id uuid,
  municipio_name text,
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
  where ga.area_type = 'MUNICIPIO'
    and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY', 'COMMUNITY')
    and se.occurred_at >= (now() - (months_back || ' months')::interval)
  group by ga.id;
$$;
