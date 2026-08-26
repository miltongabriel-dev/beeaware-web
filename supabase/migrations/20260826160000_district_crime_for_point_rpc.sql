-- BeeAware Brasil roadmap — district-level crime for a single point.
--
-- Neither cisp_crime_summary (all districts, statewide) nor a bare
-- ST_Contains lookup (area_hierarchy_for_point/dp_for_point, no crime
-- counts) is quite what a tap-to-inspect screen needs: one round trip
-- that finds the containing police district (CISP or DP — whichever
-- area_type the tapped point's state actually has geometry for, exactly
-- the same area_type in ('CISP','DP') generalization cisp_crime_summary
-- itself uses) and returns its own crime breakdown, or an empty result
-- if the point isn't inside any such polygon yet (most of Brazil, still
-- — only RJ and SP have this geometry so far). The Flutter client never
-- needs to know which state/area_type it got; that's the whole point of
-- keeping this generic rather than a per-state RPC.
create function district_crime_for_point(
  point_lat double precision,
  point_lng double precision,
  months_back integer default 3
)
returns table (
  district_id uuid,
  district_name text,
  state_code text,
  violence_count bigint,
  property_count bigint,
  public_safety_count bigint,
  total_count bigint
)
language sql
stable
as $$
  with pt as (
    select ST_SetSRID(ST_MakePoint(point_lng, point_lat), 4326) as geom
  ),
  district as (
    select ga.id, ga.name, ga.state_code
    from geo_areas ga, pt
    where ga.area_type in ('CISP', 'DP')
      and ST_Contains(ga.geometry, pt.geom)
    limit 1
  )
  select
    district.id,
    district.name,
    district.state_code,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'VIOLENCE'), 0),
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'PROPERTY'), 0),
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'PUBLIC_SAFETY'), 0),
    coalesce(sum(se.occurrence_count), 0)
  from district
  left join security_events se
    on se.geo_area_id = district.id
    and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY')
    and se.occurred_at >= (now() - (months_back || ' months')::interval)
  group by district.id, district.name, district.state_code;
$$;

grant execute on function district_crime_for_point(double precision, double precision, integer) to anon, authenticated;
