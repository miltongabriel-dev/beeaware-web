-- Verify the 15-state geometry backfill (AC/AL/AM/AP/BA/CE/MG/PB/PE/PI/
-- RN/RO/RR/SE/TO) fixed municipality_crime_summary()'s output.
do $$
declare
  r record;
  total int;
begin
  select count(*) into total from municipality_crime_summary();
  raise notice 'municipality_crime_summary total rows: %', total;

  for r in
    select state_code, count(*) as n
    from municipality_crime_summary()
    group by state_code
    order by state_code
  loop
    raise notice 'state=% municipalities_with_data=%', r.state_code, r.n;
  end loop;
end $$;
