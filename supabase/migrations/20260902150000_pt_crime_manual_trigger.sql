-- BeeAware Global roadmap — one-off manual trigger for PtCrimeAdapter's
-- first real run, same reasoning as 20260831160000's UK manual trigger:
-- verifying the adapter end-to-end (308 concelhos, real DGPJ crime
-- counts, geo_area_id linking) without waiting for next month's cron
-- slot. Not itself scheduled — a single net.http_post using the same
-- vault-secret pattern the cron migration already established.
select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('adapter', 'PtCrimeAdapter')
);
