-- One-off read-only diagnostic: EXPLAIN ANALYZE the query behind
-- concelho_crime_summary to find the actual bottleneck (indexes already
-- exist on security_events.geo_area_id per 20260825250000/20260825270000
-- -- ~1 second for 306 groups seemed high given that).
do $$
declare
  r record;
  plan_text text := '';
begin
  for r in
    execute $q$
      explain (analyze, buffers, format text)
      select
        ga.id,
        ga.name,
        ga.country_code,
        ga.geometry,
        coalesce(sum(se.occurrence_count) filter (where se.event_category = 'VIOLENCE'), 0),
        coalesce(sum(se.occurrence_count) filter (where se.event_category = 'PROPERTY'), 0),
        coalesce(sum(se.occurrence_count) filter (where se.event_category in ('PUBLIC_SAFETY', 'ROAD_SAFETY')), 0),
        coalesce(sum(se.occurrence_count), 0)
      from geo_areas ga
      join security_events se on se.geo_area_id = ga.id
      where ga.area_type = 'CONCELHO'
        and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY', 'ROAD_SAFETY')
        and se.occurred_at >= (now() - interval '24 months')
      group by ga.id
    $q$
  loop
    plan_text := plan_text || r."QUERY PLAN" || E'\n';
  end loop;
  raise notice '%', plan_text;
end $$;
