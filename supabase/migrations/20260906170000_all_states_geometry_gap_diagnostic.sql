-- One-off read-only diagnostic: user reports MANY states lost the
-- choropleth (not just PA/MA, already fixed). Check every state that
-- has real municipality-linked security_events data against its
-- geo_areas geometry coverage, to find every state with the same
-- "data exists, geometry never backfilled" gap in one pass.
do $$
declare
  r record;
begin
  for r in
    select
      se.state_code,
      count(distinct se.city_ibge_code) as distinct_munis_with_data,
      count(*) as total_events,
      max(se.occurred_at) as latest_event
    from security_events se
    where se.city_ibge_code is not null
      and se.country_code = 'BR'
      and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY')
      and se.occurred_at >= (now() - interval '3 months')
    group by se.state_code
    order by se.state_code
  loop
    raise notice 'state=% munis_with_recent_data=% events=% latest=%',
      r.state_code, r.distinct_munis_with_data, r.total_events, r.latest_event;
  end loop;

  raise notice '--- geometry coverage per state ---';
  for r in
    select state_code, count(*) as total, count(geometry) as with_geometry
    from geo_areas
    where area_type = 'MUNICIPALITY' and country_code = 'BR'
    group by state_code
    order by state_code
  loop
    raise notice 'state=% total_munis=% with_geometry=%', r.state_code, r.total, r.with_geometry;
  end loop;
end $$;
