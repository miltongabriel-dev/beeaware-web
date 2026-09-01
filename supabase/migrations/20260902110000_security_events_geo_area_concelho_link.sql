-- BeeAware Global roadmap — Portugal, link security_events to CONCELHO geometry.
--
-- Same trigger widened twice already (CISP->+DP, then +POLICE_FORCE) —
-- widening it again here to include 'CONCELHO' is safe for the same
-- reason those migrations gave: Portuguese concelho names ("Sintra",
-- "Cascais", "Lisboa") don't collide with any CISP/DP/POLICE_FORCE name
-- already in geo_areas, so the shared name-match trigger still can't
-- cross-link the wrong tier.
create or replace function resolve_security_event_geo_area()
returns trigger
language plpgsql
as $$
begin
  if new.geo_area_id is null and new.district is not null then
    select id into new.geo_area_id
    from geo_areas
    where area_type in ('CISP', 'DP', 'POLICE_FORCE', 'CONCELHO')
      and country_code = new.country_code
      and name = new.district
    limit 1;
  end if;
  return new;
end;
$$;
