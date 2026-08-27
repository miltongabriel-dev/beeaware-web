-- BeeAware Brasil roadmap / Phase 6 — News Intelligence, consumption RPC.
--
-- G1NewsAdapter (g1_news.ts) has been writing sourceType='news' rows to
-- security_events since 20260827110000's cron went live, but nothing
-- reads them yet: nearby_security_events requires EXACT/STREET
-- geo_precision (a real point), and every municipality-keyed RPC
-- (recent_activity_within_state, historical_safety_within_state, ...)
-- joins on city_ibge_code — this source has neither (see g1_news.ts's own
-- header for why guessing a municipality from a G1 region-slug would
-- invent precision the source doesn't have). This RPC is the first
-- consumer of the STATE geo_precision tier confidence.ts already had a
-- location_confidence value for but nothing used until now.
--
-- Resolves state_code by spatial containment against geo_areas'
-- MUNICIPALITY polygons (IbgeAdapter, already backfilled — see
-- backfill_sp_municipality_geometry.sql/backfill_remaining_municipality_
-- geometry.sql) rather than asking the caller to pass a state_code
-- directly: the client already has a lat/lng for both "user's current
-- location" and "a searched address" (reverseGeocode in geocoding.dart
-- only returns a free-text state NAME from Nominatim, e.g. "São Paulo",
-- which isn't the 2-letter UF this table is keyed on) — same
-- point-in first, resolve-area second shape as area_hierarchy_for_point.
-- A point with no containing municipality (outside Brazil, over water)
-- simply returns no rows rather than erroring.
create function nearby_news(
  point_lat double precision,
  point_lng double precision,
  max_results integer default 10,
  max_age_days integer default 30
)
returns table (
  id uuid,
  state_code text,
  event_category security_event_category,
  event_type text,
  severity text,
  occurred_at timestamptz,
  title text,
  subtitle text,
  article_url text,
  source_organisation text
)
language sql
stable
as $$
  with pt as (
    select ST_SetSRID(ST_MakePoint(point_lng, point_lat), 4326) as geom
  ),
  containing_municipality as (
    select ga.state_code
    from geo_areas ga, pt
    where ga.area_type = 'MUNICIPALITY'
      and ga.country_code = 'BR'
      and ST_Contains(ga.geometry, pt.geom)
    limit 1
  )
  select
    se.id,
    se.state_code,
    se.event_category,
    se.event_type,
    se.severity,
    se.occurred_at,
    se.raw_payload ->> 'title' as title,
    se.raw_payload ->> 'subtitle' as subtitle,
    se.raw_payload ->> 'link' as article_url,
    ss.organisation as source_organisation
  from security_events se
  join containing_municipality cm on cm.state_code = se.state_code
  left join security_sources ss on ss.id = se.source_id
  where se.source_type = 'news'
    and se.occurred_at >= (now() - (max_age_days || ' days')::interval)
  order by se.occurred_at desc
  limit max_results;
$$;

grant execute on function nearby_news(double precision, double precision, integer, integer) to anon, authenticated;
