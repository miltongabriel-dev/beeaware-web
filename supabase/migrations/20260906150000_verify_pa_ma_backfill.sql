-- Verify the PA/MA geometry backfill (triggered directly, outside a
-- migration) actually fixed municipality_crime_summary()'s output.
do $$
declare
  r record;
  pa_count int;
  ma_count int;
begin
  select count(*) into pa_count from municipality_crime_summary() where state_code = 'PA';
  select count(*) into ma_count from municipality_crime_summary() where state_code = 'MA';
  raise notice 'municipality_crime_summary: PA=% MA=%', pa_count, ma_count;

  for r in
    select state_code, count(*) as n
    from municipality_crime_summary()
    group by state_code
    order by state_code
  loop
    raise notice 'state=% municipalities_with_data=%', r.state_code, r.n;
  end loop;
end $$;
