-- One-off: backfill municipality geometry for every other state found
-- missing it while investigating the SP gap (20260826170000) — turned
-- out SP wasn't special, RJ and RS are the only two states that ever
-- had backfillGeometry() run for them. MG, BA, AL, MT, ES and PA all
-- have real crime data (their own adapters: mg_ssp.ts, ba_ssp.ts,
-- al_seds.ts, mt_sesp.ts, es_sesp.ts, pa_segup.ts) whose choropleth
-- entries are equally unreachable from the map today. Same
-- fire-and-forget net.http_post pattern as 20260825280000/20260826170000.
select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('action', 'backfill-geometry', 'stateCode', 'MG')
);

select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('action', 'backfill-geometry', 'stateCode', 'BA')
);

select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('action', 'backfill-geometry', 'stateCode', 'AL')
);

select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('action', 'backfill-geometry', 'stateCode', 'MT')
);

select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('action', 'backfill-geometry', 'stateCode', 'ES')
);

select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('action', 'backfill-geometry', 'stateCode', 'PA')
);
