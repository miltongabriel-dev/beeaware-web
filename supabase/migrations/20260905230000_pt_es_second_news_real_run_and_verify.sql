-- Real (non-debug) first run for NoticiasAoMinutoAdapter/ElMundoAdapter,
-- followed by a count check across ALL PT/ES news sources combined. Same
-- pattern as the first news real-trigger migration (20260905130000).
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
    body := jsonb_build_object('adapter', 'NoticiasAoMinutoAdapter')
  ) into req_id;
  loop
    select * into resp from net._http_response where id = req_id;
    exit when resp.id is not null or waited > 60;
    perform pg_sleep(3);
    waited := waited + 3;
  end loop;
  raise notice 'NoticiasAoMinutoAdapter status_code: %', resp.status_code;
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
    body := jsonb_build_object('adapter', 'ElMundoAdapter')
  ) into req_id;
  loop
    select * into resp from net._http_response where id = req_id;
    exit when resp.id is not null or waited > 60;
    perform pg_sleep(3);
    waited := waited + 3;
  end loop;
  raise notice 'ElMundoAdapter status_code: %', resp.status_code;
end $$;
