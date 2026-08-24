-- BeeAware Brasil roadmap / Phase 2 — AlAdapter scheduler.
--
-- Monthly, matching the source's own update cadence. Measured reliable in
-- production: two consecutive real-mode runs both wrote an identical
-- 21071 rows (idempotent) — the whole file is small (2.5MB, 21294 rows),
-- no memory-limit risk.
select cron.schedule(
  'ingest-al-seds-monthly',
  '25 4 * * 1', -- 04:25 UTC every Monday, alongside the other weekly Brazil-state slots
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'AlAdapter')
  );
  $$
);
