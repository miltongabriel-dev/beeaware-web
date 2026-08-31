-- BeeAware Brasil roadmap — PrSespAdapter scheduler.
--
-- Weekly, same as every other CSV/HTML/PDF source with no fixed
-- publication schedule of its own. See pr_sesp.ts's own header: this
-- adapter's source URL is a pinned quarterly-report snapshot with no
-- automated discovery mechanism, so weekly re-fetches don't pick up a
-- new quarter on their own — they just keep this source's health check
-- current until someone manually updates STATS_PDF_URL.
select cron.schedule(
  'ingest-pr-sesp-weekly',
  '5 5 * * 1', -- 05:05 UTC every Monday, next slot after MS-SEJUSP (05:00)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'PrSespAdapter')
  );
  $$
);
