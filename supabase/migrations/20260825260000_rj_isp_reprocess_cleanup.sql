-- BeeAware Brasil roadmap / Phase 4 — clean up before RjIspAdapter
-- reprocesses at CISP granularity.
--
-- rj_isp.ts moved from one row per (municipality, month, event type) to
-- one row per (CISP, month, event type) now that real CISP geometry
-- exists. The new sourceRecordId format ("cisp{id}-{ym}-{type}") shares
-- nothing with the old one ("{city_ibge_code}-{ym}-{type}"), so the
-- upsert's onConflict (source_id, source_record_id) would never match
-- the old rows — they'd just sit there as stale MUNICIPALITY-precision
-- duplicates of the same underlying counts, double-counting anything
-- that sums by municipality (municipality_crime_summary, the
-- Historical/Recent Safety Pulse RPCs, etc). Delete them explicitly
-- instead of leaving that footgun for the adapter's next scheduled run
-- to silently create.
delete from security_events
where source_id = (select id from security_sources where adapter_name = 'RjIspAdapter')
  and geo_precision = 'MUNICIPALITY';
