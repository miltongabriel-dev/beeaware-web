-- One-off read-only diagnostic: user reports some Brazilian states
-- (e.g. Pará) disappeared from the municipality choropleth. Check
-- current server time, municipality_crime_summary's real output count,
-- and per-adapter health/last_success for the Brazilian state sources.
do $$
declare
  r record;
  total_munis int;
  pa_munis int;
  started timestamptz;
begin
  raise notice 'now(): %', now();

  started := clock_timestamp();
  select count(*) into total_munis from municipality_crime_summary();
  raise notice 'municipality_crime_summary() elapsed_ms=%', extract(epoch from (clock_timestamp() - started)) * 1000;
  raise notice 'municipality_crime_summary total rows: %', total_munis;

  select count(*) into pa_munis
  from municipality_crime_summary()
  where state_code = 'PA';
  raise notice 'municipality_crime_summary rows for PA: %', pa_munis;

  for r in
    select state_code, count(*) as n
    from municipality_crime_summary()
    group by state_code
    order by state_code
  loop
    raise notice 'state=% municipalities_with_data=%', r.state_code, r.n;
  end loop;

  for r in
    select adapter_name, active, last_check, last_success, last_data_date
    from security_sources
    where adapter_name in (
      'PaSegupAdapter', 'PrfAccidentsAdapter', 'RenaestAdapter', 'RjIspAdapter',
      'MgAdapter', 'EsSespAdapter', 'AlAdapter', 'MtAdapter', 'DfAdapter',
      'PeAdapter', 'GoSspAdapter', 'MaSspAdapter', 'MsSejuspAdapter',
      'PrSespAdapter', 'RrPcrrAdapter', 'RsSspAdapter', 'FbspAnuarioAdapter'
    )
    order by last_success asc nulls first
  loop
    raise notice 'adapter=% active=% last_check=% last_success=% last_data_date=%',
      r.adapter_name, r.active, r.last_check, r.last_success, r.last_data_date;
  end loop;
end $$;
