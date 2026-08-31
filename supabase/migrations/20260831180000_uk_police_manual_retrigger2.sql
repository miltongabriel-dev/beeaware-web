-- BeeAware Global roadmap — second diagnostic re-trigger for
-- UkPoliceAdapter, to observe whether security_events rows accumulate
-- gradually (pointing at an Edge Function execution-time kill mid-run) or
-- converge quickly to a small final count (pointing at data.police.uk
-- itself rejecting most concurrent requests from this origin).
select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('adapter', 'UkPoliceAdapter')
);
