-- BeeAware Brasil roadmap — scheduler + ingestion support.
--
-- Two things:
-- 1. Fix a real inconsistency found while wiring the ingestion job:
--    geo_areas.geometry was NOT NULL, but IbgeAdapter (Phase 1) only
--    produces territorial identity (country/state/city_ibge_code/name) —
--    polygons come from IBGE's separate /malhas endpoint, deliberately
--    deferred (see supabase/functions/_shared/adapters/br/ibge.ts).
--    A NOT NULL geometry column would reject every row IBGE writes today.
-- 2. Unique constraints so ingestion can upsert idempotently instead of
--    accumulating duplicate rows on every scheduled run, and the pg_cron
--    schedule that calls the ingest-security-sources Edge Function at
--    each source's documented cadence (roadmap 12.6).

alter table geo_areas alter column geometry drop not null;

alter table geo_areas
  add constraint geo_areas_natural_key
  unique (country_code, state_code, city_ibge_code, area_type);

alter table security_sources
  add constraint security_sources_adapter_name_key
  unique (adapter_name);

alter table security_events
  add constraint security_events_source_record_key
  unique (source_id, source_record_id);

-- ===== Scheduling =====
-- pg_net's HTTP call needs the service_role key as a bearer token, and
-- that must NOT be a literal value in a committed migration file. It's
-- read here via current_setting('app.settings.service_role_key', true),
-- which returns NULL until someone sets it directly on the database —
-- once, outside of any migration:
--
--   alter database postgres set app.settings.service_role_key = '<service_role_key>';
--
-- Run that by hand (via the SQL editor or `supabase db execute`) after
-- applying this migration and before expecting these jobs to actually
-- succeed. Until then, the scheduled calls will fire but fail auth —
-- visible in `select * from cron.job_run_details order by start_time desc;`.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

-- Replace <project-ref> only if this project is ever forked/renamed —
-- brjzkdtkmewbodpqjhkj is the linked BeeAware project as of 2026-08-21.
select cron.schedule(
  'ingest-ibge-monthly',
  '0 3 1 * *', -- 03:00 UTC on the 1st of each month — roadmap 12.6: IBGE = monthly
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'IbgeAdapter')
  );
  $$
);

select cron.schedule(
  'ingest-sinesp-daily',
  '0 4 * * *', -- roadmap 12.6: SINESP = daily
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'SinespAdapter')
  );
  $$
);

select cron.schedule(
  'ingest-prf-daily',
  '15 4 * * *', -- roadmap 12.6: PRF = daily (offset 15min from SINESP to avoid both hitting at once)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'PrfAccidentsAdapter')
  );
  $$
);

select cron.schedule(
  'ingest-renaest-weekly',
  '30 4 * * 1', -- roadmap 12.6: RENAEST = weekly (Mondays)
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'RenaestAdapter')
  );
  $$
);
