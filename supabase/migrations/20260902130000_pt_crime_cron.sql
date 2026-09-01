-- BeeAware Global roadmap — PtCrimeAdapter scheduler.
--
-- Monthly, not weekly: DGPJ only republishes annually (see pt_crime.ts's
-- header), so there's nothing to gain from checking more often. First day
-- of the month, after security-events-retention-cleanup (0 4 1 * *).
select cron.schedule(
  'ingest-pt-crime-monthly',
  '45 5 1 * *', -- 05:45 UTC on the 1st of every month
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'PtCrimeAdapter')
  );
  $$
);
