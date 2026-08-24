-- BeeAware Brasil roadmap / Phase 2 hardening — RsSspAdapter scheduler.
--
-- RsSspAdapter's own file (rs_ssp.ts) already scopes normalize() to a
-- single-month rolling window to reduce write-phase memory pressure, but
-- even the READ path (decompressing the source's ~95MB CSV) measured
-- genuinely flaky in production after that fix: 7 identical debug-mode
-- requests, 3 succeeded and 4 hit WORKER_RESOURCE_LIMIT — this source's
-- file size is right at this Edge Function's memory ceiling, not
-- reliably under it, and Supabase gives no per-function memory/CPU
-- tuning to raise that ceiling from here.
--
-- Rather than block registering this adapter on solving that (a genuinely
-- different execution architecture — chunked/incremental writes across
-- multiple invocations — is the real fix, and a bigger lift than this
-- pass), lean on two things this ingestion pipeline already guarantees:
-- upserts are idempotent (onConflict source_id,source_record_id — a
-- successful retry of an already-written month is a safe no-op) and a
-- failed run writes nothing (fails closed, never partially corrupts). So:
-- run weekly instead of monthly, even though the source itself only
-- publishes monthly — at a measured ~40-50% single-attempt success rate,
-- weekly retries put the odds of at least one success within a given
-- month north of 90%, without needing response-aware retry logic in SQL
-- (pg_net's net.http_post is fire-and-forget from a cron job's
-- perspective; polling for a synchronous retry-on-failure would be a
-- separate, heavier build).
--
-- Superseded by 20260824110000_rs_ssp_cron_daily.sql shortly after this
-- one was first applied: real (non-debug, write-enabled) mode turned out
-- to succeed far less often than this comment assumed (~12.5%, not
-- ~40-50% — that number was debug-mode-only), so weekly wasn't enough
-- margin. Left as-is (not edited) to keep migration history honest;
-- see the later migration for the corrected cadence and reasoning.
select cron.schedule(
  'ingest-rs-ssp-weekly',
  '30 5 * * 1', -- 05:30 UTC every Monday, offset from FCDO (05:00 daily)
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
