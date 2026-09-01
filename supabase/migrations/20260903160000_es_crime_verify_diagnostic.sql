-- One-off read-only diagnostic (no schema change), same pattern as
-- 20260902160000: verify EsCrimeAdapter's first real run wrote events,
-- linked geo_area_id, and that municipio_es_crime_summary now returns
-- real rows.
do $$
declare
  r record;
begin
  for r in
    select count(*) as n,
           count(*) filter (where geo_area_id is not null) as linked,
           count(distinct district) as distinct_municipios,
           min(occurred_at) as min_occurred_at,
           max(occurred_at) as max_occurred_at
    from security_events
    where country_code = 'ES'
  loop
    raise notice 'ES events: n=% linked=% distinct_municipios=% occurred_at=%..%',
      r.n, r.linked, r.distinct_municipios, r.min_occurred_at, r.max_occurred_at;
  end loop;

  for r in select event_category, count(*) as n from security_events where country_code = 'ES' group by 1 order by 1 loop
    raise notice 'category %: %', r.event_category, r.n;
  end loop;

  for r in select count(*) as n from municipio_es_crime_summary() loop
    raise notice 'municipio_es_crime_summary() rows now: %', r.n;
  end loop;

  for r in select municipio_name, total_count from municipio_es_crime_summary() order by total_count desc limit 5 loop
    raise notice 'top: % = %', r.municipio_name, r.total_count;
  end loop;
end $$;
