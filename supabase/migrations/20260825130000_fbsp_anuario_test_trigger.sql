-- One-off: manually trigger FbspAnuarioAdapter once to verify the newly
-- deployed adapter against the real, live Edge Function (not just the
-- local Python simulation used to validate its parsing logic before
-- writing the TypeScript). net.http_post is fire-and-forget from SQL (see
-- 20260824100000_rs_ssp_cron.sql's own comment on this) — the actual
-- result is checked afterward by querying security_sources/security_events
-- directly, not from this statement's own return value.
select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('adapter', 'FbspAnuarioAdapter')
);
