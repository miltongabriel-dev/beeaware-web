-- BeeAware map: revert municipality_crime_summary's window back to 3 months.
--
-- 20260824160000_municipality_crime_summary_window.sql widened the default
-- from 3 to 12 months, intending a "longer historical view than the map's
-- 2-month cutoff". In production this instead makes the query scan enough
-- security_events rows to hit Postgres's statement timeout (confirmed live:
-- months_back=12 -> error 57014 "canceling statement due to statement
-- timeout"; months_back=3 -> succeeds in ~3.5s, RJ+RS data included).
--
-- BrazilCrimeSummaryApi.fetchSummary() catches every RPC error and returns
-- an empty list ("offline-friendly by design"), so this failure was
-- completely silent client-side: the whole Brazil choropleth (every state,
-- not just one) stopped rendering, which is what showed up as "RJ/RS data
-- isn't loading". lib/backend/brazil_crime_summary_api.dart's own default
-- is reverted to 3 alongside this migration — it's the one that actually
-- matters, since the only caller (HomeScreen) never passes an explicit
-- months_back and so always used whichever default was in Dart.
--
-- Properly widening this again needs a supporting index on security_events
-- (city_ibge_code, country_code, occurred_at) first, not just a bigger
-- window — left for a follow-up, not attempted here blind.
create or replace function municipality_crime_summary(months_back integer default 3)
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
