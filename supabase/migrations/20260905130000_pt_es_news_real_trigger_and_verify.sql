-- Real (non-debug) first run for PtNewsAdapter/EsNewsAdapter — writes
-- actual security_events rows — followed by verification that
-- geo_area_id resolved and nearby_news_pins now returns rows for both
-- countries (Lisboa/Madrid), same pattern as the PT/ES crime adapters'
-- own manual-trigger + verify migrations.
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
    body := jsonb_build_object('adapter', 'PtNewsAdapter')
  ) into req_id;
  loop
    select * into resp from net._http_response where id = req_id;
    exit when resp.id is not null or waited > 60;
    perform pg_sleep(2);
    waited := waited + 2;
  end loop;
  raise notice 'PtNewsAdapter real run status_code: %', resp.status_code;
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
    body := jsonb_build_object('adapter', 'EsNewsAdapter')
  ) into req_id;
  loop
    select * into resp from net._http_response where id = req_id;
    exit when resp.id is not null or waited > 60;
    perform pg_sleep(2);
    waited := waited + 2;
  end loop;
  raise notice 'EsNewsAdapter real run status_code: %', resp.status_code;
end $$;

-- Verify: rows landed, geo_area_id resolved, and the widened
-- nearby_news_pins RPC actually returns them.
do $$
declare
  r record;
begin
  for r in
    select country_code, count(*) as n, count(geo_area_id) as with_geo_area
    from security_events
    where source_type = 'news' and country_code in ('PT', 'ES')
    group by country_code
  loop
    raise notice 'security_events: country=% total=% geo_area_id_set=%', r.country_code, r.n, r.with_geo_area;
  end loop;

  -- Lisboa
  for r in select count(*) as n from nearby_news_pins(38.7223, -9.1393, 50000) loop
    raise notice 'nearby_news_pins near Lisboa: %', r.n;
  end loop;

  -- Madrid
  for r in select count(*) as n from nearby_news_pins(40.4168, -3.7038, 50000) loop
    raise notice 'nearby_news_pins near Madrid: %', r.n;
  end loop;
end $$;
