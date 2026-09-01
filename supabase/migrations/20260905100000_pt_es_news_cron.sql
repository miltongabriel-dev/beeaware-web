-- BeeAware Global blueprint — PtNewsAdapter/EsNewsAdapter schedulers.
--
-- Same 4-hourly cadence and idempotency reasoning as BbcNewsAdapter's own
-- cron (20260828100000_bbc_news_cron.sql): both feeds refresh
-- continuously through the day, and sourceRecordId is each article's own
-- guid, so re-fetching the same feed window repeatedly is naturally a
-- no-op via the upsert on (source_id, source_record_id). Offset from
-- BBC's :25 and G1's :10 slots.
select cron.schedule(
  'ingest-pt-news-4h',
  '35 */4 * * *', -- :35 past every 4th hour UTC
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'PtNewsAdapter')
  );
  $$
);

select cron.schedule(
  'ingest-es-news-4h',
  '40 */4 * * *', -- :40 past every 4th hour UTC
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'EsNewsAdapter')
  );
  $$
);
