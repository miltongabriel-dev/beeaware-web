-- Follow-up-only check for 20260905290000's request id 310.
do $$
declare
  resp record;
begin
  select * into resp from net._http_response where id = 310;
  if resp.id is null then
    raise notice 'still no response for id 310';
  else
    raise notice 'status_code: %', resp.status_code;
    raise notice 'content: %', left(resp.content, 3000);
  end if;
end $$;
