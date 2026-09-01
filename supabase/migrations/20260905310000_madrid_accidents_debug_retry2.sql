-- Retry of 20260905290000's debug run after restructuring fetch() to
-- return one aggregated RawSecurityRecord instead of ~11,500 individual
-- ones (see madrid_accidents.ts's own header for why the previous shape
-- likely hung on raw_events' unbatched insert).
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
    body := jsonb_build_object('adapter', 'MadridAccidentsAdapter', 'debug', true)
  ) into req_id;
  raise notice 'request id: %', req_id;
  loop
    select * into resp from net._http_response where id = req_id;
    exit when resp.id is not null or waited > 90;
    perform pg_sleep(3);
    waited := waited + 3;
  end loop;
  if resp.id is null then
    raise notice 'no response after % seconds', waited;
  else
    raise notice 'status_code: %', resp.status_code;
    raise notice 'content: %', left(resp.content, 3000);
  end if;
end $$;
