-- Follow-up to 20260909120000 — that migration's output got truncated
-- before the FR/DE sections and the total count scrolled into view.
-- Re-checking just those here.
do $$
declare
  r record;
  total int;
begin
  select count(*) into total from security_events where source_record_id like 'manual-%';
  raise notice 'TOTAL BACKFILLED: %', total;
  for r in
    select country_code, count(*) as n from security_events
    where source_record_id like 'manual-%' group by 1 order by 1
  loop
    raise notice '  % = %', r.country_code, r.n;
  end loop;

  raise notice '--- FR pins (nearby_news_pins, 90d) ---';
  for r in
    select city, event_type, lat, lng, occurred_at from nearby_news_pins(46.6, 2.2, 1200000, 200, 90)
    where country_code = 'FR' order by occurred_at desc
  loop
    raise notice 'FR % % (%, %) %', r.city, r.event_type, r.lat, r.lng, r.occurred_at;
  end loop;

  raise notice '--- DE pins (nearby_news_pins, 90d) ---';
  for r in
    select city, event_type, lat, lng, occurred_at from nearby_news_pins(51.1657, 10.4515, 1200000, 200, 90)
    where country_code = 'DE' order by occurred_at desc
  loop
    raise notice 'DE % % (%, %) %', r.city, r.event_type, r.lat, r.lng, r.occurred_at;
  end loop;
end $$;
