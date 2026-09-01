-- BeeAware Brasil roadmap — one-off geometry backfill for Pará and
-- Maranhão, same reasoning as backfill_sp_municipality_geometry.sql/
-- backfill_remaining_municipality_geometry.sql.
--
-- User report (2026-09-06): "alguns estados... como o Pará" disappeared
-- from the municipality choropleth. Investigated live, not assumed
-- (20260906120000/130000/140000, kept in history): municipality_
-- crime_summary() genuinely returned zero rows for PA and MA, but the
-- underlying security_events data was fine — 1242 municipality-linked PA
-- rows and 213 for MA, both with occurred_at as recent as today, real
-- VIOLENCE/PROPERTY/PUBLIC_SAFETY categories, nothing wrong with
-- PaSegupAdapter/MaSspAdapter's own ingestion. The real cause: geo_areas
-- had ZERO municipalities with geometry for either state (0 of 144 for
-- PA, 0 of 217 for MA) — municipality_crime_summary() requires
-- `ga.geometry is not null`, so every PA/MA row was silently excluded
-- regardless of how much fresh crime data existed. These two states were
-- never included in either prior geometry backfill migration (RJ/SP were
-- backfilled first since they had the earliest municipality-level
-- adapters; "remaining" states in 20260826180000 apparently didn't yet
-- include PA/MA at the time, and nothing backfilled them since).
--
-- Already run once directly against the deployed function (not via
-- net.http_post) during live investigation — confirmed
-- municipalitiesSeen=144/geometryWritten=144 for PA and
-- municipalitiesSeen=217/geometryWritten=217 for MA, and
-- municipality_crime_summary() then returned 95 PA and 105 MA
-- municipalities (not all 144/217 have recent enough crime data to
-- appear, which is expected). Re-running here via the same
-- net.http_post + vault-secret pattern every other manual trigger in
-- this project uses, for the historical record — backfillGeometry is
-- idempotent (a plain UPDATE keyed by city_ibge_code), so redoing it is
-- harmless.
select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('action', 'backfill-geometry', 'stateCode', 'PA')
);

select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('action', 'backfill-geometry', 'stateCode', 'MA')
);
