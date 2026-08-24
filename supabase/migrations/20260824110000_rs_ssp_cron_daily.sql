-- BeeAware Brasil roadmap / Phase 2 hardening — RsSspAdapter scheduler,
-- corrected cadence.
--
-- 20260824100000_rs_ssp_cron.sql scheduled this weekly based on debug-mode
-- (read + aggregate only) success measurements (~40-50%). Testing real,
-- write-enabled mode directly afterward — the mode the cron job actually
-- runs — showed a much lower success rate: 1 success in 8 attempts
-- (~12.5%), because the batch-upsert write loop measurably adds its own
-- further memory risk on top of an already-marginal read phase. At that
-- real rate, weekly (4 attempts/month) only reaches ~59% odds of any
-- success in a given month — not a real fix. Daily (~30 attempts/month)
-- reaches >98% (1 - 0.875^30). Same reasoning as before on why retrying
-- is safe: upserts are idempotent (onConflict source_id,
-- source_record_id) and a failed run writes nothing.
--
-- cron.schedule with an existing job name updates it in place rather than
-- creating a duplicate; cron.unschedule removes the superseded weekly job
-- outright rather than leaving two jobs both trying to run this adapter.
select cron.unschedule('ingest-rs-ssp-weekly');

select cron.schedule(
  'ingest-rs-ssp-daily',
  '30 5 * * *', -- 05:30 UTC daily, offset from FCDO (05:00 daily)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'RsSspAdapter')
  );
  $$
);
