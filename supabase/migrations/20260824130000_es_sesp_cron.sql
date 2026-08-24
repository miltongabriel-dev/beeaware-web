-- BeeAware Brasil roadmap / Phase 2 — EsSespAdapter scheduler.
--
-- Monthly, matching the source's own update cadence. Measured reliable in
-- production: two consecutive real-mode runs both wrote an identical
-- 43498 rows (idempotent), no memory-limit issues — this file (2.4MB,
-- 43834 rows) is far under the ceiling other Brazilian sources have hit.
select cron.schedule(
  'ingest-es-sesp-monthly',
  '20 4 * * 1', -- 04:20 UTC every Monday, alongside PA-SEGUP/MG-SSP's weekly slot
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'EsSespAdapter')
  );
  $$
);
