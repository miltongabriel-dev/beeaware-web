-- BeeAware Global roadmap — UkPoliceAdapter scheduler.
--
-- Weekly, same reasoning as MS-SEJUSP/PR-SESP's own weekly schedules for
-- a source that itself only republishes monthly: a weekly check costs
-- little and picks up data.police.uk's occasional late revisions to the
-- most recent month without waiting a full month, since ingestion is
-- idempotent (upsert on sourceRecordId per force/month/eventType).
select cron.schedule(
  'ingest-uk-police-weekly',
  '15 5 * * 1', -- 05:15 UTC every Monday, next slot after RR-PCRR (05:10)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'UkPoliceAdapter')
  );
  $$
);
