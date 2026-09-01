-- Follow-up-only check for 20260905200000's real trigger, which timed
-- out its own 93s poll before the write landed (11 sequential-ish
-- council fetches take longer than the debug/single-adapter runs this
-- session has seen before). No new trigger here.
do $$
declare
  r record;
begin
  for r in
    select count(*) as n, count(geo_area_id) as with_geo_area, count(distinct district) as councils
    from security_events
    where source_id = (select id from security_sources where adapter_name = 'NiPoliceAdapter')
  loop
    raise notice 'security_events for NiPoliceAdapter: total=% geo_area_id_set=% distinct_councils=%', r.n, r.with_geo_area, r.councils;
  end loop;

  for r in select lgd_name, total_count from lgd_crime_summary() order by total_count desc loop
    raise notice 'lgd_crime_summary: % -> %', r.lgd_name, r.total_count;
  end loop;
end $$;
