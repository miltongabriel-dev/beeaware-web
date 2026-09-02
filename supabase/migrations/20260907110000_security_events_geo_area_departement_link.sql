-- BeeAware Global roadmap — France, link security_events to département
-- geometry.
--
-- Same trigger widened six times already (CISP->+DP->+POLICE_FORCE->
-- +CONCELHO->+MUNICIPIO->+LGD) — widening it again here to include
-- 'DEPARTEMENT' is safe for the same reason: French département names
-- ("Ain", "Paris", "Guadeloupe") don't collide with any other tier's
-- name already in geo_areas because the trigger also filters by
-- country_code (France is the first 'FR' entry in geo_areas — no other
-- tier exists for this country yet).
create or replace function resolve_security_event_geo_area()
returns trigger
language plpgsql
as $$
begin
  if new.geo_area_id is null and new.district is not null then
    select id into new.geo_area_id
    from geo_areas
    where area_type in ('CISP', 'DP', 'POLICE_FORCE', 'CONCELHO', 'MUNICIPIO', 'LGD', 'DEPARTEMENT')
      and country_code = new.country_code
      and name = new.district
    limit 1;
  end if;
  return new;
end;
$$;
