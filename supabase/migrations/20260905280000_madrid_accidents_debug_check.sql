-- Follow-up-only check for 20260905270000's debug request id 308, which
-- timed out its own 93s poll.
do $$
declare
  resp record;
begin
  select * into resp from net._http_response where id = 308;
  if resp.id is null then
    raise notice 'still no response for id 308';
  else
    raise notice 'status_code: %', resp.status_code;
    raise notice 'content: %', left(resp.content, 3000);
  end if;
end $$;
