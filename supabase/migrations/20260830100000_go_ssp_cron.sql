-- BeeAware Brasil roadmap / Phase 8 (second-wave states) — GoSspAdapter
-- scheduler.
--
-- Monthly, matching the source's own cadence (SSP-GO republishes the
-- current year's PDF progressively as months close — see go_ssp.ts's own
-- header). Every run re-fetches all 2018-2025 individual-year PDFs (each
-- 20-40KB), not just the current year, so no rolling-window migration is
-- needed the way RS-SSP/PA-SEGUP needed one.
select cron.schedule(
  'ingest-go-ssp-monthly',
  '50 4 * * 1', -- 04:50 UTC every Monday, next slot after PE-SDS (04:35) and PA-SEGUP (04:45)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'GoSspAdapter')
  );
  $$
);
