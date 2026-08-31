-- BeeAware Global roadmap — re-trigger UkPoliceAdapter after fixing the
-- fetch() concurrency bug (20260831160000's run registered a successful
-- healthCheck but wrote zero events: 43 forces fetched strictly
-- sequentially took long enough that the whole invocation was killed
-- before fetch() ever returned, so normalize()/upsert never ran). Same
-- one-off net.http_post pattern, now against the bounded-concurrency
-- fetch().
select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('adapter', 'UkPoliceAdapter')
);
