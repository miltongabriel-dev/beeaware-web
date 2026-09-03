-- BeeAware Global blueprint — fix location_coverage timing out again
-- under real load, second time.
--
-- location_coverage() (20260904160000) already fixed its EXACT/point
-- branch with a bbox prefilter against the geometry GIST index, but its
-- second branch (COUNTRY-precision rows, which have no location at all)
-- was left as a plain filter with no supporting index — fine when
-- security_events was smaller, but confirmed live today via EXPLAIN
-- ANALYZE (after this session's official-data audit added ~18,700 new
-- MT/MA/MS rows, growing the table to 333k+): that branch does a full
-- Seq Scan over the whole table, alone accounting for ~7.2s of a 7.5s
-- total run — comfortably enough, under concurrent load (four other
-- choropleth RPCs firing at once on cold app load, same contention
-- pattern 20260904160000's own header describes), to blow the anon
-- role's 15s statement_timeout and surface as the map's markers/
-- hexagons silently failing to load (a 500 from location_coverage,
-- confirmed live via a real headless-browser run against production).
--
-- Partial index scoped to exactly what this branch filters on (location
-- IS NULL, i.e. COUNTRY-precision rows only — every other geo_precision
-- always has a location) so it stays small and cheap to maintain rather
-- than indexing the whole table on these columns.
create index if not exists security_events_country_coverage_idx
  on security_events (country_code, geo_precision)
  where location is null;
