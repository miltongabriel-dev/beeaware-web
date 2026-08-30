-- BeeAware Brasil roadmap — news-derived map pins.
--
-- nearby_security_events (20260821170000) deliberately excludes anything
-- coarser than EXACT/STREET geo_precision — the roadmap's geographic-
-- honesty rule (section 7.2). News items (geo_text_match.ts) only ever
-- resolve a city or state name from article text, never a coordinate, so
-- they've never been eligible for that RPC and only ever surfaced in the
-- separate nearby_news text feed (20260827120000+).
--
-- This is a second, distinct pin source rather than relaxing that rule:
-- when a news article was matched down to a real municipality
-- (geo_precision = 'MUNICIPALITY', city_ibge_code set — see g1_news.ts's
-- and national_pt_news.ts's city-level matching), the municipality's own
-- polygon centroid (geo_areas, backfilled by IbgeAdapter) is a genuine,
-- if approximate, point to show — "somewhere in this city", not "here
-- exactly". STATE-only matches are deliberately NOT promoted to a pin at
-- all: a whole state's geometric centroid routinely lands in an empty
-- rural area nowhere near where the news actually happened, which would
-- mislead rather than inform. The client is expected to render these
-- visually distinct from EXACT/STREET pins (halo/ring instead of a solid
-- dot) precisely because the point returned here is a city-level
-- approximation, not a real coordinate — keep that distinction rather
-- than silently upgrading news to look like a confirmed record.
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
    on ga.area_type = 'MUNICIPALITY'
    and ga.country_code = se.country_code
    and ga.city_ibge_code = se.city_ibge_code
  left join security_sources ss on ss.id = se.source_id
  where se.source_type = 'news'
    and se.geo_precision = 'MUNICIPALITY'
    and se.city_ibge_code is not null
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
