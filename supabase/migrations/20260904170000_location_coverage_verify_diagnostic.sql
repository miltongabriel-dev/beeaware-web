-- One-off read-only diagnostic: confirm location_coverage runs fast
-- alone after the bbox-prefilter fix (20260904160000). Point is the same
-- Epsom, UK coordinates HomeScreen's own fallback location uses.
do $$
declare
  r record;
  started timestamptz := clock_timestamp();
begin
  for r in select count(*) as n from location_coverage(51.3339, -0.2679, 15000, 'GB') loop
    raise notice 'location_coverage() rows=% elapsed_ms=%', r.n,
      extract(epoch from (clock_timestamp() - started)) * 1000;
  end loop;
end $$;
