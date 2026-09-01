-- One-off read-only diagnostic: PA and MA are the two states missing
-- from municipality_crime_summary() (per 20260906120000). Check how
-- stale their real security_events data actually is, and whether any
-- rows exist there at all.
do $$
declare
  r record;
begin
  for r in
    select se.city_ibge_code is not null as has_muni, count(*) as n,
      max(se.occurred_at) as latest, min(se.occurred_at) as earliest
    from security_events se
    where se.state_code = 'PA'
    group by 1
  loop
    raise notice 'PA rows: has_municipality_link=% count=% latest=% earliest=%', r.has_muni, r.n, r.latest, r.earliest;
  end loop;

  for r in
    select se.city_ibge_code is not null as has_muni, count(*) as n,
      max(se.occurred_at) as latest, min(se.occurred_at) as earliest
    from security_events se
    where se.state_code = 'MA'
    group by 1
  loop
    raise notice 'MA rows: has_municipality_link=% count=% latest=% earliest=%', r.has_muni, r.n, r.latest, r.earliest;
  end loop;

  -- Also check via source_id in case state_code itself isn't populated
  -- on these rows for some reason.
  for r in
    select ss.adapter_name, count(se.id) as n, max(se.occurred_at) as latest
    from security_sources ss
    left join security_events se on se.source_id = ss.id
    where ss.adapter_name in ('PaSegupAdapter', 'MaSspAdapter')
    group by ss.adapter_name
  loop
    raise notice 'by source: adapter=% total_rows=% latest_occurred_at=%', r.adapter_name, r.n, r.latest;
  end loop;
end $$;
