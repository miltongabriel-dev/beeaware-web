-- BeeAware Brasil roadmap — RrPcrrAdapter scheduler.
--
-- Monthly, matching PC-RR/NEAC's own microdata publication cadence
-- (same reasoning as AL-SEDS/PE-SDS's own monthly schedules for
-- similarly-shaped per-victim CVLI-style microdata).
select cron.schedule(
  'ingest-rr-pcrr-monthly',
  '10 5 * * 1', -- 05:10 UTC every Monday, next slot after PR-SESP (05:05)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'RrPcrrAdapter')
  );
  $$
);
