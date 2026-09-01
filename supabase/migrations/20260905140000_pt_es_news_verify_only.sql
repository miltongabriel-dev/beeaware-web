-- Follow-up-only check for 20260905130000's real trigger: that
-- migration's own status_code read timed out at 60s per adapter (a real
-- write run — fetch + classify + per-row geo_area_id trigger + upsert —
-- takes longer than the debug-only run did), so its inline verification
-- queries ran before the writes actually landed. No new trigger here,
-- just re-checking now that more time has passed.
do $$
declare
  r record;
begin
  for r in
    select country_code, count(*) as n, count(geo_area_id) as with_geo_area
    from security_events
    where source_type = 'news' and country_code in ('PT', 'ES')
    group by country_code
  loop
    raise notice 'security_events: country=% total=% geo_area_id_set=%', r.country_code, r.n, r.with_geo_area;
  end loop;

  for r in select count(*) as n from nearby_news_pins(38.7223, -9.1393, 50000) loop
    raise notice 'nearby_news_pins near Lisboa: %', r.n;
  end loop;

  for r in select count(*) as n from nearby_news_pins(40.4168, -3.7038, 50000) loop
    raise notice 'nearby_news_pins near Madrid: %', r.n;
  end loop;
end $$;
