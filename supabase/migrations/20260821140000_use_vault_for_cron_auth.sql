-- BeeAware Brasil roadmap — fix cron auth: use Vault instead of a custom GUC.
--
-- The previous migration's cron jobs read the service_role key via
-- current_setting('app.settings.service_role_key', true), meant to be set
-- once by hand with `alter database postgres set app.settings.service_role_key
-- = '<key>'`. That fails on Supabase-managed projects:
--
--   ERROR: permission denied to set parameter "app.settings.service_role_key"
--   (SQLSTATE 42501)
--
-- The `postgres` role here isn't a true superuser, and ALTER DATABASE ... SET
-- on an arbitrary custom GUC namespace requires superuser. Supabase's own
-- recommended pattern for this exact case (secrets read from SQL, e.g. by
-- pg_cron/pg_net) is Supabase Vault instead — it's already enabled on every
-- project (confirmed: `select extname from pg_extension where extname =
-- 'supabase_vault'` returns a row) and readable by the postgres role via
-- `vault.decrypted_secrets`, no elevated privilege needed.
--
-- This migration re-points all 4 existing cron jobs at Vault. It does NOT
-- create the secret itself — that's a one-off `select vault.create_secret(
-- '<service_role_key>', 'service_role_key', ...)` run by hand, same
-- discipline as before: the literal key value must never sit in a committed
-- migration file.
--
-- cron.schedule() with an existing job name updates that job in place
-- (unschedule + reschedule under the hood), so this safely replaces the
-- command on all 4 already-running jobs.

select cron.schedule(
  'ingest-ibge-monthly',
  '0 3 1 * *',
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'IbgeAdapter')
  );
  $$
);

select cron.schedule(
  'ingest-sinesp-daily',
  '0 4 * * *',
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'SinespAdapter')
  );
  $$
);

select cron.schedule(
  'ingest-prf-daily',
  '15 4 * * *',
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'PrfAccidentsAdapter')
  );
  $$
);

select cron.schedule(
  'ingest-renaest-weekly',
  '30 4 * * 1',
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'RenaestAdapter')
  );
  $$
);
