-- One-off read-only diagnostic (no schema change): investigate why the
-- UK/PT/ES choropleths reportedly don't show colour on a cold app load
-- (they only fetch once, concurrently, on HomeScreen.initState).
do $$
declare
  r record;
begin
  for r in select now() as server_now loop
    raise notice 'server now(): %', r.server_now;
  end loop;

  for r in
    select max(occurred_at) as max_occurred, count(*) as n
    from security_events
    where country_code = 'GB'
  loop
    raise notice 'GB security_events: max_occurred_at=% n=%', r.max_occurred, r.n;
  end loop;

  -- Time the 4 choropleth RPCs individually (not concurrently) to see if
  -- ES/PT are just plain slow on their own, or only under concurrent load.
  for r in select count(*) as n from municipio_es_crime_summary() loop
    raise notice 'municipio_es_crime_summary() alone: rows=%', r.n;
  end loop;
  for r in select count(*) as n from concelho_crime_summary() loop
    raise notice 'concelho_crime_summary() alone: rows=%', r.n;
  end loop;
end $$;
