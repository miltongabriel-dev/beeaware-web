do $$
declare
  resp record;
begin
  select * into resp from net._http_response where id = 253;
  if resp.id is null then
    raise notice 'still no response row for id 253';
  else
    raise notice 'status_code: %, error_msg: %', resp.status_code, resp.error_msg;
    raise notice 'content: %', left(resp.content, 6000);
  end if;
end $$;
