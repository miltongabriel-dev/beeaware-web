-- BeeAware Brasil roadmap / Phase 8 (second-wave states) — PeAdapter
-- scheduler.
--
-- Monthly, matching the source's own update cadence (SDS-PE republishes
-- the microdata file's end-month roughly as each month closes — see
-- pe_sds.ts's own header). The whole file is 4.5MB, nothing like the
-- memory/size concerns RS-SSP/SINESP documented, so no rolling-window or
-- region-pinning migration needed alongside this one.
select cron.schedule(
  'ingest-pe-sds-monthly',
  '35 4 * * 1', -- 04:35 UTC every Monday, alongside the other weekly Brazil-state slots (MG 04:15, ES 04:20, AL 04:25, DF 04:30, PA-SEGUP 04:45)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'PeAdapter')
  );
  $$
);
