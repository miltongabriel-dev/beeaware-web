-- BeeAware Brasil roadmap / Phase 5 — Safety Pulse (Historical Safety),
-- population column.
--
-- Historical Safety needs a per-capita rate, not a raw occurrence count,
-- to be comparable across municipalities of very different sizes (the
-- roadmap's own "evidence over labels" principle) — nothing in geo_areas
-- carried population before this. Nullable: not every municipality will
-- be backfilled immediately, and historical_safety() must skip (not
-- fabricate) municipalities without a real population value.
alter table geo_areas add column population integer;
