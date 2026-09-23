-- net.http_post's own default timeout is 5000ms; RoSepogAdapter's real
-- run (municipio_fato call + ~52 concurrent natureza_fato calls + IBGE
-- lookup + DB writes) genuinely exceeds that, confirmed live: a manual
-- trigger timed out at exactly 5000ms. Same fix already applied to
-- MA-SSP and MS-SEJUSP (see their own *_cron_timeout_fix.sql) — cron.
-- schedule with an existing job name updates it in place.
select cron.schedule(
  'ingest-ro-sepog-weekly',
  '25 5 * * 1',
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'RoSepogAdapter'),
    timeout_milliseconds := 90000
  );
  $$
);
