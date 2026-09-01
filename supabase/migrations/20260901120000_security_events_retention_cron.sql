-- security_events retention (see 20260901100000_data_retention_diagnostic.sql's
-- findings): rows older than 12 months are already unused by every current
-- reader — historical_safety/historical_safety_for_city/
-- historical_safety_within_state, district_crime_for_point,
-- cisp_crime_summary, police_force_crime_summary and
-- municipality_crime_summary all default to (and are always called with)
-- months_back <= 12, never more. At the time of writing this was 60% of
-- the table's rows (176,815 of 295,227). Each row is already a monthly
-- aggregate per area/category (occurrence_count), not a raw per-incident
-- record, so there is nothing further to compact — deleting is the actual
-- effect a compaction step would have had anyway. canonical_event_id is a
-- self-referencing FK for the not-yet-built dedup engine (roadmap 7.4) and
-- is null on every row today, so this delete cannot violate it.
--
-- Monthly, not daily: this table grows far slower than raw_events
-- (~15k rows/month, ~12 MB/month) so a tight loop buys nothing.
select cron.schedule(
  'security-events-retention-cleanup',
  '0 4 1 * *', -- 04:00 UTC on the 1st of every month
  $$ delete from security_events where occurred_at < now() - interval '12 months'; $$
);
