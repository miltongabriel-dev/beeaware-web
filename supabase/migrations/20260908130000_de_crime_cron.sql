-- BeeAware Global roadmap — DeCrimeAdapter scheduler.
--
-- Monthly: BKA publishes a closed annual year, once a year (see
-- de_crime.ts's header) — nothing to gain from checking more often.
-- First day of the month, next free slot after ingest-fbsp-anuario-monthly
-- (06:15 UTC) — 06:00 is already ingest-unodc-monthly's slot.
select cron.schedule(
  'ingest-de-crime-monthly',
  '20 6 1 * *', -- 06:20 UTC on the 1st of every month
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'DeCrimeAdapter')
  );
  $$
);
