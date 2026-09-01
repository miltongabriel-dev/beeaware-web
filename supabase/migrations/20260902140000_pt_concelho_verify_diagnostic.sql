-- One-off read-only diagnostic (no schema change), same pattern as
-- 20260901100000_data_retention_diagnostic.sql: verify the 308-row PT
-- concelho geometry landed correctly and concelho_crime_summary runs
-- clean before PtCrimeAdapter ever writes a row.
do $$
declare
  r record;
begin
  for r in select count(*) as n from geo_areas where country_code = 'PT' and area_type = 'CONCELHO' loop
    raise notice 'geo_areas PT/CONCELHO rows: %', r.n;
  end loop;

  for r in select count(*) as n from concelho_crime_summary() loop
    raise notice 'concelho_crime_summary() rows (should be 0, no events ingested yet): %', r.n;
  end loop;
end $$;
