-- Verify the nearby_news_pins fix (20260908170000) actually surfaces
-- France/Germany news pins now.
do $$
declare
  r record;
  fr_count int;
  de_count int;
begin
  select count(*) into fr_count
  from nearby_news_pins(46.6, 2.2, 1200000, 200, 3650)
  where country_code = 'FR';
  raise notice 'FR pins from nearby_news_pins (radius 1200km around center of France): %', fr_count;

  select count(*) into de_count
  from nearby_news_pins(51.1657, 10.4515, 1200000, 200, 3650)
  where country_code = 'DE';
  raise notice 'DE pins from nearby_news_pins (radius 1200km around center of Germany): %', de_count;

  for r in
    select country_code, city, event_type, lat, lng, occurred_at
    from nearby_news_pins(46.6, 2.2, 1200000, 200, 3650)
    where country_code in ('FR', 'DE')
    union all
    select country_code, city, event_type, lat, lng, occurred_at
    from nearby_news_pins(51.1657, 10.4515, 1200000, 200, 3650)
    where country_code in ('FR', 'DE')
  loop
    raise notice 'pin: % % % (%, %) at %', r.country_code, r.city, r.event_type, r.lat, r.lng, r.occurred_at;
  end loop;
end $$;
