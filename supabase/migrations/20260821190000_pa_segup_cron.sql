-- BeeAware Brasil roadmap — PaSegupAdapter scheduler.
--
-- Weekly, not daily: /download_recorte on codec.segup.pa.gov.br
-- regenerates its export server-side on every request and has been
-- observed taking anywhere from ~60s to 500s+ (see pa_segup.ts's file
-- header) — daily would just mean daily risk of the run failing for no
-- reason on this end. If a run does fail, healthCheck() reports RED and
-- the following week's run just tries again; nothing is lost since the
-- ingested window (trailing 1 month, see MONTHS_WINDOW in pa_segup.ts)
-- overlaps the previous run's.
select cron.schedule(
  'ingest-pa-segup-weekly',
  '45 4 * * 1', -- Mondays, offset from the other weekly/monthly jobs
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'PaSegupAdapter')
  );
  $$
);
