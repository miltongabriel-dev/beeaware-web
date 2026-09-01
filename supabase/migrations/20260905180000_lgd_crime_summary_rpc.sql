-- BeeAware Global roadmap — Northern Ireland LGD choropleth summary RPC.
--
-- Same shape as police_force_crime_summary (20260904110000) — same
-- 6-month window (a live source with its own real-world reporting lag,
-- same reasoning as that migration's own header), same 3-bucket
-- violence/property/public_safety split with everything else (here:
-- NiPoliceAdapter's COMMUNITY-category rows, same CATEGORY_MAP as
-- UkPoliceAdapter since it's the same national taxonomy) still counted
-- in total_count but not broken into its own named bucket, matching how
-- England & Wales' own choropleth already handles it.
--
-- Groups by ga.id alone (not ga.id, ga.name, ga.country_code,
-- ga.geometry) from the start here — the earlier concelho/municipio
-- timeout investigation (20260904120000/130000) found that grouping by
-- a full PostGIS geometry column forces expensive per-row geometry
-- hashing; Postgres's functional-dependency simplification lets
-- ga.name/ga.country_code/ga.geometry be selected without needing them
-- in GROUP BY, since ga.id is geo_areas' actual primary key.
create or replace function lgd_crime_summary(months_back integer default 6)
returns table (
  lgd_id uuid,
  lgd_name text,
  country_code text,
  geometry geometry,
  violence_count bigint,
  property_count bigint,
  public_safety_count bigint,
  total_count bigint
)
language sql
stable
as $$
  select
    ga.id,
    ga.name,
    ga.country_code,
    ga.geometry,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'VIOLENCE'), 0) as violence_count,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'PROPERTY'), 0) as property_count,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'PUBLIC_SAFETY'), 0) as public_safety_count,
    coalesce(sum(se.occurrence_count), 0) as total_count
  from geo_areas ga
  join security_events se on se.geo_area_id = ga.id
  where ga.area_type = 'LGD'
    and se.occurred_at >= (now() - (months_back || ' months')::interval)
  group by ga.id;
$$;

grant execute on function lgd_crime_summary(integer) to anon, authenticated;
