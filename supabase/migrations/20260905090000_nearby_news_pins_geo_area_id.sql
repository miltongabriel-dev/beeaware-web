-- BeeAware Global blueprint — widen nearby_news_pins (20260830120000) to
-- also resolve PT/ES (and any future non-Brazil country) news pins.
--
-- This RPC's join only ever matched Brazil's own city_ibge_code column
-- (ga.city_ibge_code = se.city_ibge_code) — PT/ES security_events rows
-- have no IBGE code at all, they're linked by geo_area_id directly via
-- resolve_security_event_geo_area() (20260903110000, already widened to
-- cover CONCELHO/MUNICIPIO). Adding an OR branch on geo_area_id keeps the
-- Brazilian path byte-for-byte identical while giving PT/ES (and any
-- future country using the same geo_area_id trigger) a working join,
-- without needing a second RPC or any Flutter-side change — IncidentStore
-- already calls this same RPC for every viewport in the world (see
-- brazil_news_pins_api.dart).
create or replace function nearby_news_pins(
  center_lat double precision,
  center_lng double precision,
  radius_meters double precision,
  max_results integer default 200,
  max_age_days integer default 60
)
returns table (
  id uuid,
  country_code text,
  state_code text,
  city text,
  state text,
  event_category security_event_category,
  event_type text,
  original_category text,
  severity text,
  occurred_at timestamptz,
  title text,
  subtitle text,
  article_url text,
  source_organisation text,
  lat double precision,
  lng double precision
)
language sql
stable
as $$
  select
    se.id,
    se.country_code,
    se.state_code,
    se.city,
    se.state,
    se.event_category,
    se.event_type,
    se.original_category,
    se.severity,
    se.occurred_at,
    se.raw_payload ->> 'title' as title,
    se.raw_payload ->> 'subtitle' as subtitle,
    se.raw_payload ->> 'link' as article_url,
    ss.organisation as source_organisation,
    ST_Y(ST_Centroid(ga.geometry)) as lat,
    ST_X(ST_Centroid(ga.geometry)) as lng
  from security_events se
  join geo_areas ga
    on (
      (ga.area_type = 'MUNICIPALITY' and ga.country_code = se.country_code
        and ga.city_ibge_code = se.city_ibge_code)
      or (se.geo_area_id is not null and ga.id = se.geo_area_id)
    )
  left join security_sources ss on ss.id = se.source_id
  where se.source_type = 'news'
    and se.geo_precision = 'MUNICIPALITY'
    and (se.city_ibge_code is not null or se.geo_area_id is not null)
    and se.occurred_at >= (now() - (max_age_days || ' days')::interval)
    and ST_DWithin(
      ST_Centroid(ga.geometry)::geography,
      ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography,
      radius_meters
    )
  order by ST_Centroid(ga.geometry)::geography <-> ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography
  limit max_results;
$$;

grant execute on function nearby_news_pins(double precision, double precision, double precision, integer, integer)
  to anon, authenticated;
