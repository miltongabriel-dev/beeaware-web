-- BeeAware Global roadmap — one-off manual trigger for EsCrimeAdapter's
-- first real run, same reasoning as the UK/Portugal manual triggers:
-- verifying the adapter end-to-end (427 municipios, real Ministerio del
-- Interior crime counts, geo_area_id linking) without waiting for next
-- month's cron slot.
select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('adapter', 'EsCrimeAdapter')
);
