-- BeeAware Brasil roadmap / Phase 5 — one-time backfill for a real gap
-- found while validating Historical Safety for Belém: PaSegupAdapter
-- (pa_segup.ts) never set cityIbgeCode on any event it ever wrote —
-- every PA-SEGUP row had city_ibge_code null, making Belém invisible to
-- any RPC that joins on it (historical_safety AND
-- municipality_crime_summary — the choropleth never had Belém data
-- either, not just Safety Pulse). Fixed going forward in pa_segup.ts
-- (BELEM_IBGE_CODE, hardcoded since this adapter only ever fetches
-- Belém); this backfills the rows that already exist.
--
-- Scoped to event_category, not state_code alone: PRF's ROAD_SAFETY
-- rows for Pará ALSO have null city_ibge_code (a separate, pre-existing
-- gap covering many different PA municipalities, not just Belém — real,
-- but out of scope for this fix and NOT safe to touch here, since
-- blanket-assigning Belém's code to Marabá/Novo Progresso/etc. PRF rows
-- would be a real data-corruption bug, not a fix). PA-SEGUP is the only
-- Pará-state adapter that ever writes VIOLENCE/PROPERTY/PUBLIC_SAFETY
-- rows, so this WHERE clause reaches exactly (and only) its rows.
update security_events
set city_ibge_code = '1501402'
where state_code = 'PA'
  and event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY')
  and city_ibge_code is null;
