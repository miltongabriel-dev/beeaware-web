-- Re-verify after widening nearby_security_events' window to 90 days.
do $$
declare
  r record;
begin
  for r in select count(*) as n from nearby_security_events(40.4168, -3.7038, 5000) loop
    raise notice 'nearby_security_events near Madrid centre (5km, 90d): %', r.n;
  end loop;
  for r in select count(*) as n from nearby_security_events(40.4168, -3.7038, 15000) loop
    raise notice 'nearby_security_events near Madrid centre (15km, 90d): %', r.n;
  end loop;
end $$;
