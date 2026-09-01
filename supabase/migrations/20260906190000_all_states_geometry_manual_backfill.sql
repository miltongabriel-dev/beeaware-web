-- BeeAware Brasil roadmap — one-off geometry backfill for the 14
-- remaining states with zero municipality geometry, plus a re-run for
-- Minas Gerais (only 57 of 853 municipalities had geometry).
--
-- Follow-up to 20260906160000 (PA/MA): the user's report of "muitos
-- estados" (many states, not just Pará) losing the choropleth turned out
-- to be exactly right — investigated live (20260906170000, kept in
-- history), every one of Brazil's 27 states already has real, recent
-- (within days) municipality-linked crime data (mostly via
-- PrfAccidentsAdapter/RenaestAdapter's national federal-highway coverage,
-- which reaches every state regardless of whether that state also has
-- its own dedicated adapter), but 14 states had ZERO municipalities with
-- geometry in geo_areas: AC, AL, AM, AP, BA, CE, PB, PE, PI, RN, RO, RR,
-- SE, TO. MG was severely partial (57 of 853). Only DF/ES/GO/MS/MT/PA/
-- PR/RJ/RS/SC/SP (and now MA) had full coverage — the earlier RJ/SP/
-- "remaining states" backfill migrations simply never reached this
-- particular set.
--
-- Already run once directly against the deployed function during live
-- investigation — every one of the 15 states backfilled at 100%
-- (municipalitiesSeen == geometryWritten), municipality_crime_summary()
-- went from 1,125 to 2,311 total municipalities across all 27 states,
-- confirmed visually over Salvador (BA, previously zero). Re-running
-- here via net.http_post for the historical record, same as
-- 20260906160000 — backfillGeometry is idempotent.
do $$
declare
  st text;
  states text[] := array['AC','AL','AM','AP','BA','CE','MG','PB','PE','PI','RN','RO','RR','SE','TO'];
begin
  foreach st in array states loop
    perform net.http_post(
      url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object('action', 'backfill-geometry', 'stateCode', st)
    );
  end loop;
end $$;
