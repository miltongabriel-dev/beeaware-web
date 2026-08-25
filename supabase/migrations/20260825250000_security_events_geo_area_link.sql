-- BeeAware Brasil roadmap / Phase 4 — link security_events to real
-- CISP/AISP/RISP geometry (the RJ Geo migrations just before this one).
--
-- security_events already has city_ibge_code for MUNICIPALITY-precision
-- joins, but nothing structured for a finer area like a CISP — only the
-- free-text `district` column. Adding geo_area_id (nullable — only
-- adapters with real sub-municipality geometry available will ever set
-- it) gives a real FK to geo_areas instead of a name string a query
-- would have to re-match every time.
--
-- Resolving it via a BEFORE INSERT/UPDATE trigger (rather than making
-- every adapter/the ingestion function do the geo_areas lookup itself)
-- means RjIspAdapter's normalize() only needs to keep setting
-- `district` to a value that matches a geo_areas.name — the trigger
-- does the join once, here, and any future adapter that starts setting
-- `district` to a matching CISP/AISP/RISP name gets the same resolution
-- for free. Scoped to area_type = 'CISP' specifically (not RISP/AISP
-- too) since that's the only granularity any adapter's `district` field
-- is expected to name today — widening this to also try AISP/RISP names
-- would risk a wrong match if a state ever names two different-tier
-- areas the same string, which "CISP {n}"/"AISP {n}"/"RISP {n}" doesn't
-- collide on today but isn't guaranteed to stay that way forever.
alter table security_events add column geo_area_id uuid references geo_areas (id);
create index security_events_geo_area_id_idx on security_events (geo_area_id);

-- Supports both this trigger's own lookup and any future CISP-level
-- query joining security_events.geo_area_id back to geo_areas.
create index geo_areas_area_type_name_idx on geo_areas (area_type, name);

create function resolve_security_event_geo_area()
returns trigger
language plpgsql
as $$
begin
  if new.geo_area_id is null and new.district is not null then
    select id into new.geo_area_id
    from geo_areas
    where area_type = 'CISP'
      and country_code = new.country_code
      and name = new.district
    limit 1;
  end if;
  return new;
end;
$$;

create trigger security_events_resolve_geo_area
  before insert or update on security_events
  for each row execute function resolve_security_event_geo_area();
