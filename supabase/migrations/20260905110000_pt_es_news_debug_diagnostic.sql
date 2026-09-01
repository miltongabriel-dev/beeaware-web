-- One-off diagnostic: verify PtNewsAdapter/EsNewsAdapter end-to-end
-- (fetch + classify + concelho/município match) with debug:true (no DB
-- writes) before relying on the real cron run, same pattern as
-- 20260831190000's UK diagnostic.
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
    body := jsonb_build_object('adapter', 'PtNewsAdapter', 'debug', true)
  ) into req_id;

  raise notice 'PtNewsAdapter request id: %', req_id;

  loop
    select * into resp from net._http_response where id = req_id;
    exit when resp.id is not null or waited > 60;
    perform pg_sleep(2);
    waited := waited + 2;
  end loop;

  if resp.id is null then
    raise notice 'PtNewsAdapter: no response after % seconds', waited;
  else
    raise notice 'PtNewsAdapter status_code: %, error_msg: %', resp.status_code, resp.error_msg;
    raise notice 'PtNewsAdapter content: %', left(resp.content, 4000);
  end if;
end $$;

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
    body := jsonb_build_object('adapter', 'EsNewsAdapter', 'debug', true)
  ) into req_id;

  raise notice 'EsNewsAdapter request id: %', req_id;

  loop
    select * into resp from net._http_response where id = req_id;
    exit when resp.id is not null or waited > 60;
    perform pg_sleep(2);
    waited := waited + 2;
  end loop;

  if resp.id is null then
    raise notice 'EsNewsAdapter: no response after % seconds', waited;
  else
    raise notice 'EsNewsAdapter status_code: %, error_msg: %', resp.status_code, resp.error_msg;
    raise notice 'EsNewsAdapter content: %', left(resp.content, 4000);
  end if;
end $$;
