-- BeeAware Global blueprint — NiPoliceAdapter scheduler.
--
-- Same weekly cadence and reasoning as UkPoliceAdapter's own cron
-- (20260831150000): data.police.uk revises its most recent month
-- occasionally, and ingestion is idempotent (upsert on sourceRecordId
-- per council/month/category), so a weekly check costs little and picks
-- up late revisions without waiting a full month.
select cron.schedule(
  'ingest-ni-police-weekly',
  '20 5 * * 1', -- 05:20 UTC every Monday, next slot after UkPoliceAdapter (05:15)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'NiPoliceAdapter')
  );
  $$
);
