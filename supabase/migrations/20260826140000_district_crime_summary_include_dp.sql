-- BeeAware Brasil roadmap — SP Geo, widen cisp_crime_summary to DP too.
--
-- 20260825270000's own header already anticipated this: "keyed
-- generically by geo_area_id/area_type='CISP' rather than hardcoding RJ,
-- so a future state with the same CISP-equivalent granularity needs no
-- schema change here, only its own geometry migration." SP's DP rows are
-- exactly that state — same district-level shape, different area_type
-- string. Widening the existing function's WHERE clause rather than
-- adding a near-duplicate dp_crime_summary; nothing in the Flutter app
-- consumes this RPC yet (checked), so there's no exposed shape to
-- preserve and no reason to keep it RJ-only. Kept the function's
-- original name and column names (cisp_area_id/cisp_name) rather than
-- renaming to something generic — renaming this now is a bigger, purely
-- cosmetic change with no functional upside, and CISP is still the
-- larger dataset of the two.
create or replace function cisp_crime_summary(months_back integer default 3)
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
  where ga.area_type in ('CISP', 'DP')
    and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY')
    and se.occurred_at >= (now() - (months_back || ' months')::interval)
  group by ga.id, ga.name, ga.state_code, ga.geometry;
$$;
