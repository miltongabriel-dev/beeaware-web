-- One-off read-only diagnostic: check the actual statement_timeout in
-- effect, and time concelho_crime_summary/municipio_es_crime_summary
-- individually (not concurrently) to see if the GROUP BY fix genuinely
-- reduced their cost or if they're just borderline either way.
do $$
declare
  r record;
  started timestamptz;
begin
  raise notice 'statement_timeout: %', current_setting('statement_timeout');

  started := clock_timestamp();
  perform count(*) from concelho_crime_summary();
  raise notice 'concelho_crime_summary() alone: elapsed_ms=%', extract(epoch from (clock_timestamp() - started)) * 1000;

  started := clock_timestamp();
  perform count(*) from municipio_es_crime_summary();
  raise notice 'municipio_es_crime_summary() alone: elapsed_ms=%', extract(epoch from (clock_timestamp() - started)) * 1000;
end $$;
