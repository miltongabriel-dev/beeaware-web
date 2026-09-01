-- One-off diagnostic: how many concelhos/municípios now have 2+ news
-- events (the minimum for the map's cluster layer to ever show a
-- numbered hexagon, maxClusterRadius in home_screen.dart) after adding
-- the second PT/ES news source.
do $$
declare
  r record;
  multi_pt int;
  multi_es int;
begin
  select count(*) into multi_pt from (
    select district from security_events
    where source_type = 'news' and country_code = 'PT'
    group by district having count(*) >= 2
  ) x;
  select count(*) into multi_es from (
    select district from security_events
    where source_type = 'news' and country_code = 'ES'
    group by district having count(*) >= 2
  ) x;
  raise notice 'PT concelhos with 2+ events: %', multi_pt;
  raise notice 'ES municípios with 2+ events: %', multi_es;

  for r in
    select district, count(*) as n from security_events
    where source_type = 'news' and country_code = 'PT'
    group by district having count(*) >= 2
    order by n desc
  loop
    raise notice 'PT % -> %', r.district, r.n;
  end loop;
end $$;
