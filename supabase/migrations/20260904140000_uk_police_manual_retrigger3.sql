-- One-off manual re-trigger for UkPoliceAdapter, same reasoning as the
-- two earlier manual retriggers — refresh whatever data.police.uk's
-- current latest published month is, now that the window fix
-- (20260904110000) means it'll actually be usable regardless of the
-- exact day this lands on.
select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('adapter', 'UkPoliceAdapter')
);
