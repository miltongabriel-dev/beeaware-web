-- BeeAware Brasil roadmap — FbspAnuarioAdapter scheduler.
--
-- Monthly, not because the Anuário itself changes that often (FBSP
-- publishes a new edition once a year, typically July) but to keep
-- security_sources' health/freshness metadata current and to pick up a
-- new edition reasonably soon after it's published — same reasoning as
-- UnodcAdapter's monthly cadence (20260823130000_unodc_cron.sql). Cheap
-- to run this often: a single ~1.4MB unauthenticated GET, no session/CSRF
-- dance, upserts are idempotent (onConflict source_id,source_record_id),
-- so a re-run against an unchanged file is a safe no-op.
select cron.schedule(
  'ingest-fbsp-anuario-monthly',
  '15 6 1 * *', -- 06:15 UTC on the 1st of each month, offset from IBGE (03:00) and UNODC (06:00)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'FbspAnuarioAdapter')
  );
  $$
);
