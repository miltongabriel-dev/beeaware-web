-- BeeAware Global roadmap — EsCrimeAdapter scheduler.
--
-- Monthly: the Ministerio del Interior publishes a few times a year
-- (quarterly-ish balances), so there's nothing to gain from checking
-- more often (see es_crime.ts's header). First day of the month, after
-- ingest-pt-crime-monthly (05:45 UTC).
select cron.schedule(
  'ingest-es-crime-monthly',
  '50 5 1 * *', -- 05:50 UTC on the 1st of every month
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'EsCrimeAdapter')
  );
  $$
);
