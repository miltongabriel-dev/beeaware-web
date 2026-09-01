-- One-off read-only diagnostic: PA/MA have fresh, municipality-linked
-- security_events rows (20260906130000) but zero rows in
-- municipality_crime_summary(), which additionally requires
-- ga.area_type='MUNICIPALITY', ga.geometry is not null, and
-- se.event_category in ('VIOLENCE','PROPERTY','PUBLIC_SAFETY'). Check
-- both conditions directly.
do $$
declare
  r record;
begin
  for r in
    select ga.state_code, count(*) as total_munis,
      count(ga.geometry) as with_geometry
    from geo_areas ga
    where ga.area_type = 'MUNICIPALITY' and ga.state_code in ('PA', 'MA')
    group by ga.state_code
  loop
    raise notice 'geo_areas: state=% total_municipalities=% with_geometry=%', r.state_code, r.total_munis, r.with_geometry;
  end loop;

  for r in
    select se.state_code, se.event_category, count(*) as n
    from security_events se
    where se.state_code in ('PA', 'MA') and se.city_ibge_code is not null
    group by se.state_code, se.event_category
    order by se.state_code, se.event_category
  loop
    raise notice 'security_events: state=% category=% count=%', r.state_code, r.event_category, r.n;
  end loop;
end $$;
