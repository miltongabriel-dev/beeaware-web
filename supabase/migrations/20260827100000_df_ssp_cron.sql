-- BeeAware Brasil roadmap / Phase 8 — DfAdapter scheduler.
--
-- Monthly, matching the source's own update cadence (SSP-DF's own file
-- notes "atualizado em DD/MM/YYYY", refreshed roughly monthly). Both
-- fetched files together are under 100KB — nothing like the memory/size
-- concerns RS-SSP/SINESP documented, so no rolling-window or region-pinning
-- migration needed alongside this one.
select cron.schedule(
  'ingest-df-ssp-monthly',
  '30 4 * * 1', -- 04:30 UTC every Monday, alongside the other weekly Brazil-state slots (MG 04:15, ES 04:20, AL 04:25, PA-SEGUP 04:45)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'DfAdapter')
  );
  $$
);
