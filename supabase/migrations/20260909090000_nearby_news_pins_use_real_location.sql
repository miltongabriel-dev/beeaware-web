-- BeeAware Global roadmap — nearby_news_pins was always pinning every
-- news event to its geo_area's CENTROID (ST_Centroid(ga.geometry)),
-- even for an event whose own `location` column already holds a real,
-- geocoded point. Every news adapter to date (Fr/De/Pt/Es/BBC) never
-- set latitude/longitude, so this never mattered in practice — but the
-- manual FR/DE/PT/ES news backfill added in
-- 20260909110000_backfill_fr_de_pt_es_news_events.sql DOES set a real
-- `location` per event (city/neighbourhood-level, geocoded via
-- Nominatim), specifically so incidents in the same country stop
-- stacking on one identical point (a département/Bundesland centroid)
-- and instead render as visually distinct, nearby pins — the whole
-- point of that backfill.
--
-- Fix: prefer se.location when set, falling back to the geo_area
-- centroid exactly as before. Strict widening — a row with no
-- location (every existing row) resolves identically to before.
--
-- Second, smaller widening: the WHERE clause required EITHER Brazil's
-- city_ibge_code+MUNICIPALITY path OR a resolved geo_area_id. A
-- backfilled event with a real geocoded point but no matching
-- geo_areas row (e.g. Rabo de Peixe/Açores, a civil parish finer than
-- any polygon this project has for Portugal) would otherwise be
-- silently dropped despite having a perfectly good coordinate. Add a
-- third path: se.location is not null, full stop.
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
    coalesce(ST_Y(se.location), ST_Y(ST_Centroid(ga.geometry))) as lat,
    coalesce(ST_X(se.location), ST_X(ST_Centroid(ga.geometry))) as lng
  from security_events se
  left join geo_areas ga
    on (
      (ga.area_type = 'MUNICIPALITY' and ga.country_code = se.country_code
        and ga.city_ibge_code = se.city_ibge_code)
      or (se.geo_area_id is not null and ga.id = se.geo_area_id)
    )
  left join security_sources ss on ss.id = se.source_id
  where se.source_type = 'news'
    and (
      se.location is not null
      or (se.geo_precision = 'MUNICIPALITY' and se.city_ibge_code is not null)
      or se.geo_area_id is not null
    )
    and se.occurred_at >= (now() - (max_age_days || ' days')::interval)
    and ST_DWithin(
      coalesce(se.location, ST_Centroid(ga.geometry))::geography,
      ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography,
      radius_meters
    )
  order by coalesce(se.location, ST_Centroid(ga.geometry))::geography
    <-> ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography
  limit max_results;
$$;

grant execute on function nearby_news_pins(double precision, double precision, double precision, integer, integer)
  to anon, authenticated;
