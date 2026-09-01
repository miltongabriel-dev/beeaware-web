-- BeeAware Global roadmap — Northern Ireland, link security_events to
-- LGD geometry.
--
-- Same trigger widened five times already (CISP->+DP->+POLICE_FORCE->
-- +CONCELHO->+MUNICIPIO) — widening it again here to include 'LGD' is
-- safe for the same reason those migrations gave: Northern Ireland
-- council names ("Belfast", "Mid Ulster") don't collide with any other
-- tier's name already in geo_areas because the trigger also filters by
-- country_code (still 'GB', same as the England & Wales POLICE_FORCE
-- tier — the two never overlap in name).
create or replace function resolve_security_event_geo_area()
returns trigger
language plpgsql
as $$
begin
  if new.geo_area_id is null and new.district is not null then
    select id into new.geo_area_id
    from geo_areas
    where area_type in ('CISP', 'DP', 'POLICE_FORCE', 'CONCELHO', 'MUNICIPIO', 'LGD')
      and country_code = new.country_code
      and name = new.district
    limit 1;
  end if;
  return new;
end;
$$;
