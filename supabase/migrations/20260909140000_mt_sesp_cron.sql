-- BeeAware Brasil roadmap / official-data coverage audit — MtAdapter
-- scheduler.
--
-- MtAdapter (mt_sesp.ts) has been fully implemented and registered in
-- ingest-security-sources/index.ts's eventAdapters map since its own
-- Phase 2 pass, but no cron.schedule for it was ever created — a real
-- gap found by auditing which Brazilian states had zero official-source
-- events despite having adapter code, not a source-side problem like
-- BaAdapter's broken TLS cert. Verified live before writing this: a
-- manual invocation with a 90s timeout (see timeout_milliseconds below
-- for why that matters) wrote 13,271 real events on the first run.
--
-- Monthly, matching the adapter's own declared refreshFrequency
-- (mt_sesp.ts source()). timeout_milliseconds is set explicitly because
-- net.http_post's own default (5000ms) is far shorter than this adapter
-- actually needs — MaSspAdapter and MsSejuspAdapter were silently timing
-- out under that default every single scheduled run (see the sibling
-- migrations fixing their crons in this same audit pass); this new cron
-- starts with the fix already in place rather than needing a second pass.
select cron.schedule(
  'ingest-mt-sesp-monthly',
  '15 5 * * 1', -- 05:15 UTC every Monday, next free slot after RR-PCRR (05:10)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'MtAdapter'),
    timeout_milliseconds := 90000
  );
  $$
);
