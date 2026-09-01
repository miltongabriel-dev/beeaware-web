-- One-off read-only diagnostic (no schema change), same pattern as
-- 20260902140000: verify the 427-row ES municipio geometry landed
-- correctly and municipio_es_crime_summary runs clean before
-- EsCrimeAdapter ever writes a row.
do $$
declare
  r record;
begin
  for r in select count(*) as n from geo_areas where country_code = 'ES' and area_type = 'MUNICIPIO' loop
    raise notice 'geo_areas ES/MUNICIPIO rows: %', r.n;
  end loop;

  for r in select count(*) as n from municipio_es_crime_summary() loop
    raise notice 'municipio_es_crime_summary() rows (should be 0, no events ingested yet): %', r.n;
  end loop;
end $$;
