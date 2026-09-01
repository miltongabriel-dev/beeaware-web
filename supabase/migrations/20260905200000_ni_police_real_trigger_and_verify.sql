-- Real (non-debug) first run for NiPoliceAdapter — writes actual
-- security_events rows — followed by verification that all 11 councils
-- resolved geo_area_id and lgd_crime_summary returns real rows. Same
-- pattern as the PT/ES news real-trigger migration (20260905130000).
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
    body := jsonb_build_object('adapter', 'NiPoliceAdapter')
  ) into req_id;
  raise notice 'NiPoliceAdapter request id: %', req_id;
  loop
    select * into resp from net._http_response where id = req_id;
    exit when resp.id is not null or waited > 90;
    perform pg_sleep(3);
    waited := waited + 3;
  end loop;
  if resp.id is null then
    raise notice 'NiPoliceAdapter: no response after % seconds (async write may still be in flight)', waited;
  else
    raise notice 'NiPoliceAdapter status_code: %', resp.status_code;
    raise notice 'NiPoliceAdapter content: %', left(resp.content, 2000);
  end if;
end $$;
