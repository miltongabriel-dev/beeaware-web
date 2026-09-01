-- BeeAware Global roadmap — widen police_force_crime_summary's default
-- window (3 -> 6 months).
--
-- Root-caused live (2026-09-01): UkPoliceAdapter only ever holds the
-- single latest data.police.uk month (max(occurred_at) was 2026-06-01),
-- refreshed by a weekly cron that hadn't run again yet. With
-- months_back=3, `now() - 3 months` from 2026-09-01 12:37 landed at
-- 2026-06-01 12:37 — a few hours AFTER that month's 00:00:00 timestamp —
-- so the RPC's own `occurred_at >= cutoff` filter excluded the only data
-- it had, returning zero rows (not an error, just an empty choropleth).
-- 3 months was always a tight fit for a source with its own 2-3 month
-- real-world reporting lag; 6 gives real headroom without the RPC's own
-- window becoming the thing that breaks first. UkCrimeSummaryApi.dart's
-- own default must change to match — it always passes months_back
-- explicitly, so this SQL default alone doesn't reach the app.
create or replace function police_force_crime_summary(months_back integer default 6)
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
