-- BeeAware Brasil roadmap / Phase 4 — RJ Geo, spatial lookup RPC.
--
-- Implements the roadmap's own "user GPS -> ST_Contains() -> CISP ->
-- AISP -> RISP -> matching statistics" pattern (4.3's diagram) directly:
-- given a coordinate, returns which CISP/AISP/RISP contain it (RISP
-- included even though it's derivable by walking parent_area_id from
-- CISP, since a caller with only a point and no CISP result yet — e.g.
-- a point outside any CISP's boundary but still in an AISP — still gets
-- a usable answer). All three are nullable in the same row rather than
-- three separate queries, since a point either falls in RJ's police-area
-- hierarchy or it doesn't — no reason to force three round-trips for
-- what's naturally one answer.
create function area_hierarchy_for_point(
  point_lat double precision,
  point_lng double precision
)
returns table (
  cisp_id uuid,
  cisp_name text,
  aisp_id uuid,
  aisp_name text,
  risp_id uuid,
  risp_name text
)
language sql
stable
as $$
  with pt as (
    select ST_SetSRID(ST_MakePoint(point_lng, point_lat), 4326) as geom
  ),
  cisp_match as (
    select ga.id, ga.name, ga.parent_area_id
    from geo_areas ga, pt
    where ga.area_type = 'CISP'
      and ST_Contains(ga.geometry, pt.geom)
    limit 1
  ),
  aisp_match as (
    select ga.id, ga.name, ga.parent_area_id
    from geo_areas ga
    where ga.id = (select parent_area_id from cisp_match)
  )
  select
    cisp_match.id, cisp_match.name,
    aisp_match.id, aisp_match.name,
    risp.id, risp.name
  from cisp_match
  left join aisp_match on true
  left join geo_areas risp on risp.id = aisp_match.parent_area_id;
$$;

grant execute on function area_hierarchy_for_point(double precision, double precision) to anon, authenticated;
