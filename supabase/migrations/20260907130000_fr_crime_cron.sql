-- BeeAware Global roadmap — FrCrimeAdapter scheduler.
--
-- Monthly: SSMSI publishes a closed annual year, once a year (see
-- fr_crime.ts's header) — nothing to gain from checking more often.
-- First day of the month, next free slot after ingest-es-crime-monthly
-- (05:50 UTC).
select cron.schedule(
  'ingest-fr-crime-monthly',
  '55 5 1 * *', -- 05:55 UTC on the 1st of every month
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'FrCrimeAdapter')
  );
  $$
);
