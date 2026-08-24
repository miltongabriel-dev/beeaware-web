-- BeeAware Brasil roadmap / Phase 2 — MgAdapter scheduler.
--
-- Monthly, matching the source's own publication cadence and RJ-ISP's
-- cron. Unlike RsSspAdapter, this one measured reliable in production
-- (3/3 real-mode runs succeeded, identical row counts each time) once
-- scoped to a 2-year window — no daily-retry workaround needed here.
select cron.schedule(
  'ingest-mg-ssp-monthly',
  '15 4 * * 1', -- 04:15 UTC every Monday, alongside PA-SEGUP's weekly slot
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'MgAdapter')
  );
  $$
);
