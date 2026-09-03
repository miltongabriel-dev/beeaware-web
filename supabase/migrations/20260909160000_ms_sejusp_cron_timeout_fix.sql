-- BeeAware Brasil roadmap / official-data coverage audit — MsSejuspAdapter
-- cron: fix silent timeout.
--
-- ingest-ms-sejusp-weekly (20260830140000) has never once appeared in
-- cron.job_run_details since it was created, despite predating the
-- following Monday's run window — a stronger symptom than MaSspAdapter's
-- (which at least logged a "succeeded" statement every week). Root cause
-- confirmed live to be the same net.http_post default-timeout problem
-- documented in the sibling MA fix (20260909150000): a manual invocation
-- with a 90s timeout completed cleanly and wrote 5,333 real events on the
-- first try, so the adapter itself was never the problem.
--
-- cron.schedule with an existing job name updates it in place.
select cron.schedule(
  'ingest-ms-sejusp-weekly',
  '0 5 * * 1',
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'MsSejuspAdapter'),
    timeout_milliseconds := 90000
  );
  $$
);
