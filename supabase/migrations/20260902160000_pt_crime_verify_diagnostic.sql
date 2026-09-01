-- One-off read-only diagnostic (no schema change), same pattern as
-- 20260901100000/20260902140000: verify PtCrimeAdapter's first real run
-- actually wrote events, linked geo_area_id, and that
-- concelho_crime_summary now returns real rows.
do $$
declare
  r record;
begin
  for r in
    select count(*) as n,
           count(*) filter (where geo_area_id is not null) as linked,
           count(distinct district) as distinct_concelhos,
           min(occurred_at) as min_occurred_at,
           max(occurred_at) as max_occurred_at
    from security_events
    where country_code = 'PT'
  loop
    raise notice 'PT events: n=% linked=% distinct_concelhos=% occurred_at=%..%',
      r.n, r.linked, r.distinct_concelhos, r.min_occurred_at, r.max_occurred_at;
  end loop;

  for r in select event_category, count(*) as n from security_events where country_code = 'PT' group by 1 order by 1 loop
    raise notice 'category %: %', r.event_category, r.n;
  end loop;

  for r in select count(*) as n from concelho_crime_summary() loop
    raise notice 'concelho_crime_summary() rows now: %', r.n;
  end loop;

  for r in select concelho_name, total_count from concelho_crime_summary() order by total_count desc limit 5 loop
    raise notice 'top: % = %', r.concelho_name, r.total_count;
  end loop;
end $$;
