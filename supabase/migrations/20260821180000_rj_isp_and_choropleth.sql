-- BeeAware Brasil roadmap — RJ-ISP violence data + choropleth RPC.
--
-- RjIspAdapter (supabase/functions/_shared/adapters/br/rj_isp.ts) ingests
-- real monthly violence/property/drug-crime counts per municipality from
-- Rio de Janeiro's ISP open data. Unlike PRF, this data has no point
-- location (individual violent-crime records with addresses aren't
-- published anywhere) — so it's consumed as a municipality-level
-- choropleth instead of map pins, using the geometry IBGE's malha API
-- backfills onto geo_areas (see backfillGeometry() in
-- ingest-security-sources/index.ts, called once by hand for stateCode
-- "RJ", not on a schedule — it's a one-off per state, not a recurring
-- sync).
--
-- municipality_crime_summary() is the read side: sums occurrence_count
-- per municipality/category over a trailing window, joined to whatever
-- geometry has been backfilled. Municipalities without geometry loaded
-- yet are excluded rather than returned geometry-less, since the client
-- can't render those anyway.
create or replace function municipality_crime_summary(months_back integer default 3)
returns table (
  city_ibge_code text,
  city_name text,
  state_code text,
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
    ga.city_ibge_code,
    ga.name,
    ga.state_code,
    ga.geometry,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'VIOLENCE'), 0) as violence_count,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'PROPERTY'), 0) as property_count,
    coalesce(sum(se.occurrence_count) filter (where se.event_category = 'PUBLIC_SAFETY'), 0) as public_safety_count,
    coalesce(sum(se.occurrence_count), 0) as total_count
  from geo_areas ga
  join security_events se
    on se.city_ibge_code = ga.city_ibge_code
   and se.country_code = ga.country_code
  where ga.area_type = 'MUNICIPALITY'
    and ga.geometry is not null
    and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY')
    and se.occurred_at >= (now() - (months_back || ' months')::interval)
  group by ga.city_ibge_code, ga.name, ga.state_code, ga.geometry;
$$;

grant execute on function municipality_crime_summary(integer) to anon, authenticated;

select cron.schedule(
  'ingest-rj-isp-monthly',
  '0 5 3 * *', -- 05:00 UTC on the 3rd of each month, after IBGE's monthly refresh
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'RjIspAdapter')
  );
  $$
);
