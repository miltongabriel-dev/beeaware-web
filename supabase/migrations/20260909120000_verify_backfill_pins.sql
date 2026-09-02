-- Verify the FR/DE/PT/ES manual news backfill (20260909110000) actually
-- landed and that nearby_news_pins (20260909090000) now returns real,
-- distinct per-incident coordinates instead of one stacked centroid.
do $$
declare
  r record;
  total_backfilled int;
  per_country record;
begin
  select count(*) into total_backfilled
  from security_events
  where source_record_id like 'manual-%';
  raise notice 'Total manually-backfilled events: %', total_backfilled;

  for per_country in
    select country_code, count(*) as n
    from security_events
    where source_record_id like 'manual-%'
    group by country_code
    order by country_code
  loop
    raise notice 'backfilled % = %', per_country.country_code, per_country.n;
  end loop;

  raise notice '--- nearby_news_pins sample (FR, center of France, 30 days) ---';
  for r in
    select country_code, city, event_type, severity, lat, lng, occurred_at
    from nearby_news_pins(46.6, 2.2, 1200000, 200, 90)
    where country_code = 'FR'
    order by occurred_at desc
  loop
    raise notice '% % % % (%, %) at %', r.country_code, r.city, r.event_type, r.severity, r.lat, r.lng, r.occurred_at;
  end loop;

  raise notice '--- nearby_news_pins sample (DE) ---';
  for r in
    select country_code, city, event_type, severity, lat, lng, occurred_at
    from nearby_news_pins(51.1657, 10.4515, 1200000, 200, 90)
    where country_code = 'DE'
    order by occurred_at desc
  loop
    raise notice '% % % % (%, %) at %', r.country_code, r.city, r.event_type, r.severity, r.lat, r.lng, r.occurred_at;
  end loop;

  raise notice '--- nearby_news_pins sample (PT) ---';
  for r in
    select country_code, city, event_type, severity, lat, lng, occurred_at
    from nearby_news_pins(39.5, -8.0, 1200000, 200, 90)
    where country_code = 'PT'
    order by occurred_at desc
  loop
    raise notice '% % % % (%, %) at %', r.country_code, r.city, r.event_type, r.severity, r.lat, r.lng, r.occurred_at;
  end loop;

  raise notice '--- nearby_news_pins sample (ES) ---';
  for r in
    select country_code, city, event_type, severity, lat, lng, occurred_at
    from nearby_news_pins(40.4, -3.7, 1200000, 200, 90)
    where country_code = 'ES'
    order by occurred_at desc
  loop
    raise notice '% % % % (%, %) at %', r.country_code, r.city, r.event_type, r.severity, r.lat, r.lng, r.occurred_at;
  end loop;
end $$;
