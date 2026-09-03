-- BeeAware Brasil roadmap / official-data coverage audit — MaSspAdapter
-- cron: fix silent timeout.
--
-- ingest-ma-ssp-weekly (20260830110000) has been "succeeding" every
-- Monday since it was created, but MA's dedicated source had zero
-- events under its own source_id the whole time — cron.job_run_details
-- only reports whether the SQL statement that fires net.http_post
-- executed, not whether the HTTP call it kicked off ever got a
-- response. net.http_post's own default timeout is 5000ms; every real
-- weekly run was being killed at that mark before the Edge Function
-- (page fetch + a second IBGE municipios lookup + parsing) could
-- finish and write anything — confirmed live via net._http_response's
-- own error_msg ("Timeout of 5000 ms reached"). A manual invocation
-- with a 60s timeout completed in well under a minute and wrote 60 real
-- events on the first try.
--
-- cron.schedule with an existing job name updates it in place — same
-- pattern as 20260824170000's sa-east-1 pin for RsSspAdapter.
select cron.schedule(
  'ingest-ma-ssp-weekly',
  '55 4 * * 1',
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'MaSspAdapter'),
    timeout_milliseconds := 90000
  );
  $$
);
