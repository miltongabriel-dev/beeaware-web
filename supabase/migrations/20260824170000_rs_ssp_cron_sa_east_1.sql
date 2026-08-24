-- BeeAware Brasil roadmap / Phase 2 hardening — RsSspAdapter, pin
-- execution to sa-east-1 (São Paulo).
--
-- Found while diagnosing SpVehicleAdapter/SinespAdapter (both new, both
-- left unregistered — see their file headers): this Supabase project
-- runs in West Europe (London) by default, and Supabase Edge Functions
-- support per-invocation regional routing via the x-region header
-- (confirmed live via the x-sb-edge-region response header). Pinning
-- SinespAdapter's fetch to sa-east-1 cut a consistent ~43-46s failure to
-- ~14-15s — a substantial, real improvement, even though it wasn't a
-- complete fix for that particular (~20MB) file on its own.
--
-- RS-SSP's own flakiness was already attributed (before this pass) to
-- memory pressure during CSV aggregation, not network distance — a
-- different root cause, so this isn't expected to fully resolve it the
-- way it helped SINESP's fetch phase. But it's a free, no-downside
-- change (same idempotent-upsert safety net, same daily retry cadence)
-- and a shorter network leg can only reduce total time spent per
-- attempt, leaving more of the budget for the actual memory-bound work —
-- worth trying in production rather than assumed not to help.
--
-- cron.schedule with an existing job name updates it in place.
select cron.schedule(
  'ingest-rs-ssp-daily',
  '30 5 * * *',
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json',
      'x-region', 'sa-east-1'
    ),
    body := jsonb_build_object('adapter', 'RsSspAdapter')
  );
  $$
);
