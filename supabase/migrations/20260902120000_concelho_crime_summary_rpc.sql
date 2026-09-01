-- BeeAware Global roadmap — Portugal concelho-level crime summary.
--
-- Same shape as police_force_crime_summary/municipality_crime_summary, one
-- difference: PtCrimeAdapter emits ROAD_SAFETY events (drink-driving,
-- driving without a licence — DGPJ's own "crimes específicos" list, no
-- PUBLIC_SAFETY-taxonomy equivalent in this source), folded into
-- public_safety_count here so the UI keeps its usual 3-colour shape.
--
-- months_back defaults to 24, not 12: DGPJ only publishes annually and
-- with a lag (the newest year available today, 2025, was already the
-- latest complete year as of September 2026), so a 12-month cutoff risks
-- excluding the only ingested year depending on when in the year this
-- runs. See PtCrimeAdapter's header for why only the latest available
-- year is ever ingested in the first place.
create function concelho_crime_summary(months_back integer default 24)
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
  group by ga.id, ga.name, ga.country_code, ga.geometry;
$$;

grant execute on function concelho_crime_summary(integer) to anon, authenticated;
