-- BeeAware map time-window fix (part 2).
--
-- Widens municipality_crime_summary's default window from 3 to 12
-- months. The map itself now uses a tight ~2-month cutoff (see
-- 20260824150000_nearby_security_events_time_window.sql and
-- IncidentApi.fetchVisibleIncidents) — the regional choropleth is the
-- app's longer-window historical view and should stay meaningfully
-- wider than the map, not narrower than it. Same signature, so
-- CREATE OR REPLACE is safe here (only the default literal changes).
create or replace function municipality_crime_summary(months_back integer default 12)
returns table (
  city_ibge_code text,
  city_name text,
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
    ga.city_ibge_code,
    ga.name,
    ga.state_code,
    ga.geometry,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'VIOLENCE'), 0) as violence_count,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'PROPERTY'), 0) as property_count,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'PUBLIC_SAFETY'), 0) as public_safety_count,
    coalesce(sum(se.occurrence_count), 0) as total_count
  from geo_areas ga
  join security_events se
    on se.city_ibge_code = ga.city_ibge_code
   and se.country_code = ga.country_code
  where ga.area_type = 'MUNICIPALITY'
    and ga.geometry is not null
    and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY')
    and se.occurred_at >= (now() - (months_back || ' months')::interval)
  group by ga.city_ibge_code, ga.name, ga.state_code, ga.geometry;
$$;
