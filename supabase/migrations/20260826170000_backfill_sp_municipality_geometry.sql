-- One-off: backfill municipality geometry for São Paulo.
--
-- Found while investigating why tapping São Paulo city on the
-- choropleth doesn't open Area Intelligence: geo_areas rows for every
-- one of SP's 645 municipalities exist (IbgeAdapter's regular identity
-- sync already created them) but geometry is null on all of them —
-- backfillGeometry() (ingest-security-sources/index.ts, the same
-- mechanism that populated RJ and RS) was simply never run for SP.
-- Same fire-and-forget net.http_post pattern as
-- 20260825280000_rj_isp_reprocess_trigger.sql — verified afterward by
-- querying geo_areas directly, not from this statement's own return
-- value (the call is async; this migration completing doesn't mean the
-- backfill has too).
select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('action', 'backfill-geometry', 'stateCode', 'SP')
);
