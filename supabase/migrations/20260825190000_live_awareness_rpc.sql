-- BeeAware Brasil roadmap / Phase 5 — Safety Pulse, Live Awareness.
--
-- Third and last Safety Pulse dimension (roadmap 1.2): "Surface current
-- or very recent signals ... 24h / 72h / 7 days". Unlike Historical
-- Safety and Recent Activity (both municipality-ranked tables, since
-- they're about comparing places), Live Awareness is inherently a
-- point/radius query — same shape as nearby_security_events, because
-- the product question is "what's happening right around here right
-- now", tied to a coordinate, not a municipality boundary.
--
-- Deliberately NOT a 0-100 score. At a 24h/72h window even Belém (the
-- one municipality with a real live feed today) only sees ~18
-- events/day averaged across an entire city, so any specific
-- neighbourhood radius is going to be 0 or 1 most of the time — turning
-- that into a ranked percentile score would manufacture false precision
-- out of near-total sparsity. A raw signal count is what the data
-- honestly supports; a scored version can follow once real usage across
-- the three pilot markets shows whether the volume is there (same
-- release-gate reasoning already applied to the other two dimensions).
--
-- Combines both sources the roadmap lists that BeeAware actually has
-- today (community reports, official EXACT/STREET events) — news and
-- 190 calls aren't built yet (Phase 6 / SP Phase 3), so they're simply
-- absent rather than faked. official_count reuses nearby_security_events'
-- own precision/radius logic (EXACT/STREET only, ST_DWithin) so a Live
-- Awareness number and the pins a user sees on the map always agree.
-- community_count mirrors IncidentApi.fetchVisibleIncidents' own
-- status='visible' filter, computed via a plain lat/lng ST_DWithin since
-- the incidents table has no stored geometry column — fine at this
-- table's scale and with a tight recency filter narrowing the candidate
-- rows first.
create function live_awareness(
  center_lat double precision,
  center_lng double precision,
  radius_meters double precision default 2000,
  window_hours integer default 24
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
  with official as (
    select se.severity
    from security_events se
    where se.location is not null
      and se.geo_precision in ('EXACT', 'STREET')
      and se.occurred_at >= (now() - (window_hours || ' hours')::interval)
      and ST_DWithin(
        se.location::geography,
        ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography,
        radius_meters
      )
  ),
  community as (
    select i.id
    from incidents i
    where i.status = 'visible'
      and i.created_at >= (now() - (window_hours || ' hours')::interval)
      and ST_DWithin(
        ST_SetSRID(ST_MakePoint(i.lng, i.lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography,
        radius_meters
      )
  )
  select
    (select count(*) from official) as official_count,
    (select count(*) filter (where severity = 'high') from official) as official_high_severity_count,
    (select count(*) from community) as community_count,
    (select count(*) from official) + (select count(*) from community) as total_count;
$$;

grant execute on function live_awareness(double precision, double precision, double precision, integer) to anon, authenticated;
