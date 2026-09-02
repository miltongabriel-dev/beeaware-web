-- BeeAware Global roadmap — fix nearby_news_pins silently excluding
-- France/Germany's news pins.
--
-- Root cause: this RPC's WHERE clause has hardcoded
-- `se.geo_precision = 'MUNICIPALITY'` since 20260830120000, back when
-- Brazil (city_ibge_code) was the only path and PT/ES (added
-- 20260905090000, also MUNICIPALITY-precision concelho/município) were
-- the only geo_area_id-linked case. FrNewsAdapter uses geoPrecision
-- 'DISTRICT' (département) and DeNewsAdapter uses 'STATE' (Bundesland)
-- — real, correctly-resolved geo_area_id rows (confirmed live: security_
-- events.geo_area_id IS set for these), but this filter silently
-- dropped every single one of them before they ever reached the map,
-- even though the join itself (line `se.geo_area_id is not null and
-- ga.id = se.geo_area_id`) never cared about geo_precision at all — the
-- MUNICIPALITY check was only ever meaningful for the Brazil
-- city_ibge_code path.
--
-- Fix: only require geo_precision = 'MUNICIPALITY' for the Brazil path
-- (city_ibge_code is not null); the geo_area_id path is valid at ANY
-- geo_precision, since resolve_security_event_geo_area() already
-- guarantees geo_area_id only gets set when a real geo_areas row
-- matched by name — no invented precision either way. This is a strict
-- widening (every row this RPC returned before still matches), so
-- PT/ES/CONCELHO/MUNICIPIO behaviour is unchanged.
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
    and (
      (se.geo_precision = 'MUNICIPALITY' and se.city_ibge_code is not null)
      or se.geo_area_id is not null
    )
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
