-- BeeAware Global roadmap — Spain municipio-level crime summary.
--
-- Same shape as concelho_crime_summary/police_force_crime_summary. One
-- difference: EsCrimeAdapter's leftover "resto_convencional" catch-all
-- (see its header — the single biggest bucket, with no further
-- breakdown in this source) is tagged COMMUNITY, folded into
-- public_safety_count here so the UI keeps its usual 3-colour shape
-- (Portugal folds ROAD_SAFETY into the same slot for the same reason —
-- each country's source has a different "leftover" category, always
-- mapped into this third bucket).
--
-- months_back defaults to 24, not 12: the Ministerio del Interior's own
-- balance is a year-to-date cumulative figure published a few times a
-- year, not a clean closed calendar year — see EsCrimeAdapter's header
-- for why only one row per (municipio, year, category) is kept and why
-- the window needs to be wide enough to survive the gap between
-- publication and this cron's own cutoff.
create function municipio_es_crime_summary(months_back integer default 24)
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
  group by ga.id, ga.name, ga.country_code, ga.geometry;
$$;

grant execute on function municipio_es_crime_summary(integer) to anon, authenticated;
