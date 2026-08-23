-- BeeAware Global blueprint — Phase 1 part 2: FcdoAdapter scheduler.
--
-- Daily, not monthly like IbgeAdapter/UnodcAdapter — travel advisories
-- change far more often than crime baselines (a single fast-moving event,
-- e.g. Ukraine, can update within days), and this ingestion is cheap
-- (~226 small JSON fetches, no memory-limit risk).
select cron.schedule(
  'ingest-fcdo-travel-advisory-daily',
  '0 5 * * *', -- 05:00 UTC daily, offset from IBGE (03:00) and UNODC (06:00 monthly)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'FcdoAdapter')
  );
  $$
);
