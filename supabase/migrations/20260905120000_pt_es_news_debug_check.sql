-- Follow-up check for 20260905110000's two request ids (297, 298) —
-- the initial 62s poll window ended before either response landed.
do $$
declare
  resp record;
begin
  for resp in select * from net._http_response where id in (297, 298) order by id loop
    raise notice 'id: %, status_code: %, error_msg: %', resp.id, resp.status_code, resp.error_msg;
    raise notice 'content: %', left(resp.content, 4000);
  end loop;
end $$;
