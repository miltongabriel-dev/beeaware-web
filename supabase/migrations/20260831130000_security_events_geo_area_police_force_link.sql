-- BeeAware Global roadmap — UK Police, link security_events to POLICE_FORCE geometry.
--
-- Same trigger 20260826130000 already widened from 'CISP' to also try
-- 'DP' (SP's police-district unit) — widening it again here to include
-- 'POLICE_FORCE' is safe for the same reason that migration gave: UK
-- force names ("Durham", "Devon & Cornwall", "Metropolitan Police") don't
-- collide with any Portuguese CISP/DP name already in geo_areas, so one
-- shared name-match trigger still can't cross-link the wrong tier.
create or replace function resolve_security_event_geo_area()
returns trigger
language plpgsql
as $$
begin
  if new.geo_area_id is null and new.district is not null then
    select id into new.geo_area_id
    from geo_areas
    where area_type in ('CISP', 'DP', 'POLICE_FORCE')
      and country_code = new.country_code
      and name = new.district
    limit 1;
  end if;
  return new;
end;
$$;
