-- Long follow-up check for request id 314 (20260905310000) — waiting
-- much longer this time to see if it's genuinely hung or just slow.
do $$
declare
  resp record;
  waited int := 0;
begin
  loop
    select * into resp from net._http_response where id = 314;
    exit when resp.id is not null or waited > 240;
    perform pg_sleep(5);
    waited := waited + 5;
  end loop;
  if resp.id is null then
    raise notice 'still no response after % additional seconds', waited;
  else
    raise notice 'status_code: %', resp.status_code;
    raise notice 'error_msg: %', resp.error_msg;
    raise notice 'content: %', left(resp.content, 3000);
  end if;
end $$;
