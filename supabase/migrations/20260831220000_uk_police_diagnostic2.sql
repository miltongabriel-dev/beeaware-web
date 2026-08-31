-- BeeAware Global roadmap — re-run the debug diagnostic after adding a
-- User-Agent header to every data.police.uk call in uk_police.ts (see its
-- header comment). pg_net's default 5000ms response-wait timeout is
-- raised to 120000ms here purely so this diagnostic can actually observe
-- the real response instead of a client-side timeout error.
do $$
declare
  req_id bigint;
  resp record;
  waited int := 0;
begin
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'UkPoliceAdapter', 'debug', true),
    timeout_milliseconds := 120000
  ) into req_id;

  raise notice 'request id: %', req_id;

  loop
    select * into resp from net._http_response where id = req_id;
    exit when resp.id is not null or waited > 110;
    perform pg_sleep(3);
    waited := waited + 3;
  end loop;

  if resp.id is null then
    raise notice 'no response after % seconds', waited;
  else
    raise notice 'status_code: %, error_msg: %', resp.status_code, resp.error_msg;
    raise notice 'content: %', left(resp.content, 6000);
  end if;
end $$;
