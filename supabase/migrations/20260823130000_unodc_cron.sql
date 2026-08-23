-- BeeAware Global blueprint — Phase 1: UnodcAdapter scheduler.
--
-- Monthly, not because the data changes that often (UNODC publishes new
-- homicide figures at most yearly, often with a lag of a year or more)
-- but to keep security_sources' health/freshness metadata current —
-- same reasoning as IbgeAdapter's monthly cadence.
select cron.schedule(
  'ingest-unodc-monthly',
  '0 6 1 * *', -- 06:00 UTC on the 1st of each month, offset from the other monthly job (IBGE, 03:00)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'UnodcAdapter')
  );
  $$
);
