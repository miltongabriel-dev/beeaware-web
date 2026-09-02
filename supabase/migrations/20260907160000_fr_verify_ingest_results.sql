-- Verify FrCrimeAdapter/FrNewsAdapter actually wrote security_events and
-- that departement_fr_crime_summary() resolves geometry + counts.
do $$
declare
  r record;
  crime_events int;
  news_events int;
  rpc_rows int;
  rpc_total bigint;
  linked_events int;
begin
  select count(*) into crime_events from security_events where country_code = 'FR' and source_type = 'official';
  select count(*) into news_events from security_events where country_code = 'FR' and source_type = 'news';
  select count(*) into linked_events from security_events where country_code = 'FR' and geo_area_id is not null;
  raise notice 'FR official (crime) events: %', crime_events;
  raise notice 'FR news events: %', news_events;
  raise notice 'FR events with geo_area_id resolved: %', linked_events;

  select count(*), coalesce(sum(total_count), 0) into rpc_rows, rpc_total from departement_fr_crime_summary();
  raise notice 'departement_fr_crime_summary rows: %, total_count sum: %', rpc_rows, rpc_total;

  for r in
    select departement_name, total_count
    from departement_fr_crime_summary()
    order by total_count desc
    limit 10
  loop
    raise notice 'top dept: % = %', r.departement_name, r.total_count;
  end loop;
end $$;
