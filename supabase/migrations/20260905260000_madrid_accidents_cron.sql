-- BeeAware Global blueprint — MadridAccidentsAdapter scheduler.
--
-- Weekly, same reasoning as UkPoliceAdapter's own cron: the source
-- itself only republishes roughly monthly, but a weekly check costs
-- little and picks up a revised/extended CSV without waiting a full
-- month, since ingestion is idempotent (upsert on source_record_id per
-- accident).
select cron.schedule(
  'ingest-madrid-accidents-weekly',
  '25 5 * * 1', -- 05:25 UTC every Monday, next slot after NiPoliceAdapter (05:20)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'MadridAccidentsAdapter')
  );
  $$
);
