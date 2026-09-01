-- One-off read-only diagnostic: confirm the pre-2025 ES row found by
-- 20260903160000 is UnodcAdapter's country-level homicide series (which
-- also targets country_code='ES'), not an EsCrimeAdapter bug — same
-- check as 20260902170000 did for Portugal.
do $$
declare
  r record;
begin
  for r in
    select source_record_id, district, geo_area_id, occurred_at, event_category, occurrence_count
    from security_events
    where country_code = 'ES' and occurred_at < '2025-01-01'
    order by occurred_at
    limit 10
  loop
    raise notice 'pre-2025: id=% district=% geo_area_id=% occurred_at=% cat=% count=%',
      r.source_record_id, r.district, r.geo_area_id, r.occurred_at, r.event_category, r.occurrence_count;
  end loop;
end $$;
