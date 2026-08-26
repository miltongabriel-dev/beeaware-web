-- BeeAware Brasil roadmap — SP Geo, adds 'DP' to geo_area_type.
--
-- Sao Paulo's police-area unit is the DP (distrito policial / delegacia)
-- — no direct equivalent already in the enum (CISP/AISP/RISP are RJ's
-- names, AIS/RA belong to other states' hierarchies). Split into its own
-- migration, ahead of the geometry insert that needs it, since Postgres
-- won't let a freshly-added enum value be used inside the same
-- transaction it was added in.
alter type geo_area_type add value 'DP';
