-- BeeAware Brasil roadmap / Phase 8 (second-wave states) — MaSspAdapter
-- scheduler.
--
-- Weekly (matches PA-SEGUP/RS-SSP's own weekly cadence for rolling-window
-- sources — see ma_ssp.ts's own header for why "weekly" over "daily"
-- despite the source itself updating "até a data de ontem").
select cron.schedule(
  'ingest-ma-ssp-weekly',
  '55 4 * * 1', -- 04:55 UTC every Monday, next slot after GO-SSP (04:50)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'MaSspAdapter')
  );
  $$
);
