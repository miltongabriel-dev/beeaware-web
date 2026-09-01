-- Verify MadridAccidentsAdapter's real run: rows landed with real
-- coordinates, and nearby_security_events (already country-agnostic —
-- see madrid_accidents.ts's own header) returns them for a Madrid point.
do $$
declare
  r record;
begin
  for r in
    select count(*) as n, count(location) as with_location,
      count(*) filter (where geo_precision = 'EXACT') as exact_count
    from security_events
    where source_id = (select id from security_sources where adapter_name = 'MadridAccidentsAdapter')
  loop
    raise notice 'security_events: total=% with_location=% exact=%', r.n, r.with_location, r.exact_count;
  end loop;

  for r in select count(*) as n from nearby_security_events(40.4168, -3.7038, 5000) loop
    raise notice 'nearby_security_events near Madrid centre (5km): %', r.n;
  end loop;
end $$;
