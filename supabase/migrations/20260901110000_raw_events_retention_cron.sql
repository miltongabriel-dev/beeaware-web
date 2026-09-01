-- raw_events retention (see 20260901100000_data_retention_diagnostic.sql's
-- findings): a write-only replay/debug store (per its own foundation
-- comment, "internal/replay use only" — nothing in production reads it)
-- that was already the single largest table in the database (337 MB)
-- after only 9 days of ingestion, since it keeps every adapter's full raw
-- fetch payload (bytea) on every run with no prior cutoff. A direct SQL
-- cron (no Edge Function round-trip needed for a plain DELETE) trims it
-- to a rolling 30-day window daily, which is ample for replay/debugging a
-- recently-discovered ingestion bug without letting it grow unbounded.
select cron.schedule(
  'raw-events-retention-cleanup',
  '30 3 * * *', -- 03:30 UTC daily
  $$ delete from raw_events where ingested_at < now() - interval '30 days'; $$
);
