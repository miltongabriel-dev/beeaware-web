-- BeeAware Global blueprint — BbcNewsAdapter scheduler.
--
-- Same 4-hourly cadence and idempotency reasoning as G1NewsAdapter's own
-- cron (20260827110000_g1_news_cron.sql): the feed refreshes continuously
-- through the day, and sourceRecordId is the article's own guid, so
-- re-fetching the same feed window repeatedly is naturally a no-op via
-- the upsert on (source_id, source_record_id).
select cron.schedule(
  'ingest-bbc-news-4h',
  '25 */4 * * *', -- :25 past every 4th hour UTC, offset from G1's :10 slot
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'BbcNewsAdapter')
  );
  $$
);
