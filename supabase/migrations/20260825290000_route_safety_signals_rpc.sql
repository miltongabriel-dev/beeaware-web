-- BeeAware Brasil roadmap / Phase 11 — Route Awareness, safety-signal
-- counting along a route.
--
-- Companion to the route-awareness Edge Function (which returns route
-- geometry only, from OpenRouteService) — this is the "250-500m buffer
-- -> recent events" half of roadmap 11.12's pipeline. Takes the route's
-- own GeoJSON LineString geometry directly (the exact path ORS
-- returned) rather than re-deriving it, so the buffer can never
-- disagree with the line actually shown on the map.
--
-- Same two-source combination as live_awareness (20260825190000):
-- official EXACT/STREET security_events plus visible community
-- incidents, since news/190 calls aren't built yet — same reasoning,
-- not repeated here. Deliberately returns raw counts, not a score, same
-- "don't manufacture precision the data doesn't support" reasoning as
-- live_awareness — a route buffer covering a whole neighbourhood over
-- 90 days has a very different, still-sparse signal density than a
-- point radius over 24h, but it's still real-world sparse for most of
-- BeeAware's current coverage, not dense enough to rank meaningfully.
--
-- 300m default buffer sits in the roadmap's own stated 250-500m range.
-- 90-day default window is wider than live_awareness's 24h (a route
-- comparison is a "how has this corridor been" question, not a
-- right-now one) but far narrower than Historical Safety's 12 months,
-- since a route-planning decision cares about recent patterns.
create function route_safety_signals(
  route_geometry jsonb,
  buffer_meters double precision default 300,
  window_days integer default 90
)
returns table (
  official_count bigint,
  official_high_severity_count bigint,
  community_count bigint,
  total_count bigint
)
language sql
stable
as $$
  with route_buffer as (
    select ST_Buffer(
      ST_SetSRID(ST_GeomFromGeoJSON(route_geometry::text), 4326)::geography,
      buffer_meters
    )::geometry as geom
  ),
  official as (
    select se.severity
    from security_events se, route_buffer
    where se.location is not null
      and se.geo_precision in ('EXACT', 'STREET')
      and se.occurred_at >= (now() - (window_days || ' days')::interval)
      and ST_Intersects(se.location, route_buffer.geom)
  ),
  community as (
    select i.id
    from incidents i, route_buffer
    where i.status = 'visible'
      and i.created_at >= (now() - (window_days || ' days')::interval)
      and ST_Intersects(
        ST_SetSRID(ST_MakePoint(i.lng, i.lat), 4326),
        route_buffer.geom
      )
  )
  select
    (select count(*) from official) as official_count,
    (select count(*) filter (where severity = 'high') from official) as official_high_severity_count,
    (select count(*) from community) as community_count,
    (select count(*) from official) + (select count(*) from community) as total_count;
$$;

grant execute on function route_safety_signals(jsonb, double precision, integer) to anon, authenticated;
