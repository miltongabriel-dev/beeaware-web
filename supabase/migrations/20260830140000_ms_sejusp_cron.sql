-- BeeAware Brasil roadmap — MsSejuspAdapter scheduler.
--
-- Weekly, matching PA-SEGUP/RS-SSP/MA-SSP's own cadence for CSV/HTML
-- sources with no fixed publication schedule of their own (the CKAN
-- resource updates on SEJUSP-MS's own cadence, not ours).
select cron.schedule(
  'ingest-ms-sejusp-weekly',
  '0 5 * * 1', -- 05:00 UTC every Monday, next slot after MA-SSP (04:55)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'MsSejuspAdapter')
  );
  $$
);
