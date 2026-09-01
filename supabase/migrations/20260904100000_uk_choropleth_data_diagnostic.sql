-- One-off read-only diagnostic: the previous check's max(occurred_at)
-- where country_code='GB' picked up ALL GB-tagged events (news, UNODC
-- homicide, etc.), not specifically UkPoliceAdapter's own POLICE_FORCE
-- rows that police_force_crime_summary actually joins against. Narrow it
-- down to match that RPC's own join exactly.
do $$
declare
  r record;
begin
  for r in
    select max(se.occurred_at) as max_occurred, count(*) as n
    from security_events se
    join geo_areas ga on ga.id = se.geo_area_id
    where ga.area_type = 'POLICE_FORCE'
  loop
    raise notice 'POLICE_FORCE-linked events: max_occurred_at=% n=%', r.max_occurred, r.n;
  end loop;
end $$;
