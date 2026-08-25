-- BeeAware Safety Pulse — supporting index for municipality-joined queries.
--
-- historical_safety()/historical_safety_within_state() (20260824190000,
-- 20260824230000) both join security_events to geo_areas on
-- (city_ibge_code, country_code) with a months_back cutoff on occurred_at,
-- same shape as municipality_crime_summary — the query the prior
-- statement-timeout fix (20260825120000) diagnosed and left a note on:
-- "Properly widening this again needs a supporting index on
-- security_events (city_ibge_code, country_code, occurred_at) first, not
-- just a bigger window." That follow-up is this migration. Confirmed live
-- the need is real, not theoretical: security_events has grown to 135k
-- rows (SINESP's 3,401-event population plus PRF's per-accident volume)
-- and historical_safety(months_back:=12) now times out (57014) without
-- this index — the existing security_events_country_state_city_idx
-- doesn't help here since state_code sits between country_code and
-- city_ibge_code in that index but isn't part of this join's predicate.
create index security_events_city_country_occurred_idx
  on security_events (city_ibge_code, country_code, occurred_at);
