-- BeeAware Global roadmap — FrNewsAdapter scheduler.
--
-- Every 4 hours, next free slot after ingest-es-news-elmundo-4h (:50
-- past every 4th hour UTC) — same cadence as every other news adapter
-- in this project.
select cron.schedule(
  'ingest-fr-news-4h',
  '55 */4 * * *', -- :55 past every 4th hour UTC
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'FrNewsAdapter')
  );
  $$
);
