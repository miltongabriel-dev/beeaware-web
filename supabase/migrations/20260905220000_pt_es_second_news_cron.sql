-- BeeAware Global blueprint — NoticiasAoMinutoAdapter/ElMundoAdapter
-- schedulers. Same 4-hourly cadence and idempotency reasoning as the
-- other news adapters (20260905100000) — offset from PtNewsAdapter's
-- :35 and EsNewsAdapter's :40 slots.
select cron.schedule(
  'ingest-pt-news-minuto-4h',
  '45 */4 * * *', -- :45 past every 4th hour UTC
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'NoticiasAoMinutoAdapter')
  );
  $$
);

select cron.schedule(
  'ingest-es-news-elmundo-4h',
  '50 */4 * * *', -- :50 past every 4th hour UTC
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'ElMundoAdapter')
  );
  $$
);
