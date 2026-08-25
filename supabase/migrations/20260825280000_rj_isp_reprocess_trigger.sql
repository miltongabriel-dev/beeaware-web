-- One-off: re-run RjIspAdapter now that normalize() emits CISP-level
-- rows instead of municipality-aggregated ones (see the rj_isp.ts and
-- 20260825250000/260000 migrations right before this). Same
-- fire-and-forget net.http_post pattern as
-- 20260825130000_fbsp_anuario_test_trigger.sql — verified afterward by
-- querying security_events/geo_areas directly, not from this
-- statement's own return value.
select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('adapter', 'RjIspAdapter')
);
