-- One-off read-only diagnostic: confirm the pre-2025 PT rows found by
-- 20260902160000 are UnodcAdapter's country-level homicide series (which
-- also targets country_code='PT'), not a PtCrimeAdapter bug.
do $$
declare
  r record;
begin
  for r in
    select source_record_id, district, geo_area_id, occurred_at, event_category, occurrence_count
    from security_events
    where country_code = 'PT' and occurred_at < '2025-01-01'
    order by occurred_at
    limit 10
  loop
    raise notice 'pre-2025: id=% district=% geo_area_id=% occurred_at=% cat=% count=%',
      r.source_record_id, r.district, r.geo_area_id, r.occurred_at, r.event_category, r.occurrence_count;
  end loop;

  for r in
    select source_record_id, district, geo_area_id
    from security_events
    where country_code = 'PT' and geo_area_id is null
    limit 5
  loop
    raise notice 'unlinked: id=% district=% geo_area_id=%', r.source_record_id, r.district, r.geo_area_id;
  end loop;
end $$;
