-- BeeAware Brasil roadmap — SP Geo, link security_events to DP geometry.
--
-- 20260825250000 resolves security_events.geo_area_id from `district`
-- but scoped strictly to area_type = 'CISP' (that migration's own header
-- explains why: avoiding a wrong match if two different-tier areas ever
-- shared a name). SP's DP names ("01º D.P. CAMPINAS" etc.) don't collide
-- with RJ's "CISP {n}" naming, so widening the same trigger to also try
-- 'DP' is safe here rather than duplicating an almost-identical trigger
-- function for one more area_type.
create or replace function resolve_security_event_geo_area()
returns trigger
language plpgsql
as $$
begin
  if new.geo_area_id is null and new.district is not null then
    select id into new.geo_area_id
    from geo_areas
    where area_type in ('CISP', 'DP')
      and country_code = new.country_code
      and name = new.district
    limit 1;
  end if;
  return new;
end;
$$;
