-- BeeAware Brasil roadmap — RoSepogAdapter scheduler.
--
-- Weekly, same cadence as the other second-wave state adapters (GO/MA/
-- MS/PR/RR) even though the underlying source only reports monthly —
-- checking weekly means a source that starts publishing a new month's
-- data mid-month is picked up within days, not up to 4 weeks late.
select cron.schedule(
  'ingest-ro-sepog-weekly',
  '25 5 * * 1', -- 05:25 UTC every Monday, next slot after RR-PCRR (05:10, 5:15 taken elsewhere)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'RoSepogAdapter')
  );
  $$
);
