-- BeeAware Global roadmap — one-off diagnostic: only 6 of 43 UK Police
-- Force fetches have succeeded across two live runs (20260831170000/
-- 20260831180000), converging within seconds rather than timing out
-- gradually — pointing at data.police.uk rejecting most concurrent
-- requests from this origin rather than an Edge Function execution-time
-- kill. Calls debug:true (no DB writes) and captures the raw pg_net
-- response via RAISE NOTICE so the real per-request failure reason
-- (status code / error body) is visible in `supabase db push` output,
-- since Edge Function console logs aren't reachable from this CLI
-- version.
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
    body := jsonb_build_object('adapter', 'UkPoliceAdapter', 'debug', true)
  ) into req_id;

  raise notice 'request id: %', req_id;

  loop
    select * into resp from net._http_response where id = req_id;
    exit when resp.id is not null or waited > 60;
    perform pg_sleep(2);
    waited := waited + 2;
  end loop;

  if resp.id is null then
    raise notice 'no response after % seconds', waited;
  else
    raise notice 'status_code: %, error_msg: %', resp.status_code, resp.error_msg;
    raise notice 'content: %', left(resp.content, 4000);
  end if;
end $$;
