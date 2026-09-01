-- Quick, single-shot check for request id 318 (20260905350000) — that
-- migration's own DO block got killed by the migration connection's own
-- 2-minute statement_timeout (SQLSTATE 57014) mid-poll, not by anything
-- wrong with the request itself, which had already been fired
-- successfully (net.http_post returned a real id before the timeout
-- hit). No polling loop here, so this can't hit that same ceiling.
do $$
declare
  resp record;
begin
  select * into resp from net._http_response where id = 318;
  if resp.id is null then
    raise notice 'still no response for id 318';
  else
    raise notice 'status_code: %, error_msg: %', resp.status_code, resp.error_msg;
    raise notice 'content: %', left(resp.content, 3000);
  end if;
end $$;
