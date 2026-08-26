-- BeeAware Brasil roadmap — SP Geo, spatial lookup RPC.
--
-- Same "user GPS -> ST_Contains() -> area" pattern as RJ's
-- area_hierarchy_for_point, but single-tier: SP's DP shapefile has no
-- parent_area_id chain to walk (see 20260826110000's header — no
-- AISP/RISP-equivalent layer in the source data), so this returns just
-- the containing DP rather than a 3-level row. Kept as its own function
-- rather than overloading area_hierarchy_for_point, since a caller there
-- would otherwise have to know to ignore aisp_id/risp_id being always
-- null for every SP point — a distinct name is clearer than a shared one
-- with silently-inapplicable columns.
create function dp_for_point(
  point_lat double precision,
  point_lng double precision
)
returns table (
  dp_id uuid,
  dp_name text
)
language sql
stable
as $$
  select ga.id, ga.name
  from geo_areas ga, (
    select ST_SetSRID(ST_MakePoint(point_lng, point_lat), 4326) as geom
  ) pt
  where ga.area_type = 'DP'
    and ST_Contains(ga.geometry, pt.geom)
  limit 1;
$$;

grant execute on function dp_for_point(double precision, double precision) to anon, authenticated;
