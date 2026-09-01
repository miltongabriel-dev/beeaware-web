-- One-off read-only diagnostic: confirm the UK re-trigger
-- (20260904140000) landed and police_force_crime_summary now returns
-- rows with the widened 6-month window.
do $$
declare
  r record;
begin
  for r in
    select max(se.occurred_at) as max_occurred, count(*) as n
    from security_events se
    join geo_areas ga on ga.id = se.geo_area_id
    where ga.area_type = 'POLICE_FORCE'
  loop
    raise notice 'POLICE_FORCE-linked events: max_occurred_at=% n=%', r.max_occurred, r.n;
  end loop;

  for r in select count(*) as n from police_force_crime_summary() loop
    raise notice 'police_force_crime_summary() default window: rows=%', r.n;
  end loop;
end $$;
