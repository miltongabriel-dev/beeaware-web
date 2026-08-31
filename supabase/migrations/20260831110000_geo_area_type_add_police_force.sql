-- BeeAware Global roadmap — UK Police, adds 'POLICE_FORCE' to geo_area_type.
--
-- England & Wales's police-area unit (43 forces, e.g. "Metropolitan
-- Police", "Devon & Cornwall") — no existing value fits (CISP/AISP/RISP/
-- AIS/RA/DP are all Brazilian state-specific hierarchies). Split into its
-- own migration, ahead of the geometry insert that needs it, same reason
-- as 20260826100000_geo_area_type_add_dp.sql: Postgres won't let a
-- freshly-added enum value be used inside the same transaction it was
-- added in.
alter type geo_area_type add value 'POLICE_FORCE';
