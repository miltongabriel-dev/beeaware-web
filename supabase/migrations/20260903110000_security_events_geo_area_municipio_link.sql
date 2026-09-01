-- BeeAware Global roadmap — Spain, link security_events to MUNICIPIO geometry.
--
-- Same trigger widened three times already (CISP->+DP, +POLICE_FORCE,
-- +CONCELHO) — widening it again here to include 'MUNICIPIO' is safe for
-- the same reason those migrations gave: Spanish municipality names
-- ("Madrid", "Barcelona") don't collide with any other tier's name
-- already in geo_areas because the trigger also filters by country_code.
create or replace function resolve_security_event_geo_area()
returns trigger
language plpgsql
as $$
begin
  if new.geo_area_id is null and new.district is not null then
    select id into new.geo_area_id
    from geo_areas
    where area_type in ('CISP', 'DP', 'POLICE_FORCE', 'CONCELHO', 'MUNICIPIO')
      and country_code = new.country_code
      and name = new.district
    limit 1;
  end if;
  return new;
end;
$$;
