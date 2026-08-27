-- BeeAware Brasil roadmap / Phase 6 — G1NewsAdapter scheduler.
--
-- Every 4 hours, not daily like the official statistics adapters: news is
-- explicitly valued here for RECENCY (roadmap 5.1 — "news sources provide
-- recency that monthly official statistics often cannot"), and the feed
-- itself refreshes continuously through the day. sourceRecordId is the
-- article's own guid/link, so re-fetching the same 100-item feed window
-- multiple times a day is naturally idempotent (upsert on source_id,
-- source_record_id) — no risk of duplicate events from overlapping runs.
select cron.schedule(
  'ingest-g1-news-4h',
  '10 */4 * * *', -- :10 past every 4th hour UTC, offset from the top-of-hour Brazil-state slots
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'G1NewsAdapter')
  );
  $$
);
