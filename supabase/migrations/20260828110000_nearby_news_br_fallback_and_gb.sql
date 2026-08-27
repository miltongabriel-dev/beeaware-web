-- BeeAware Global blueprint — nearby_news: Brazil geometry fallback + GB
-- country-level support.
--
-- Two real gaps found after the first live runs of G1NewsAdapter/
-- BbcNewsAdapter:
--
-- 1. Brazil: nearby_news's original version (20260827120000) required the
--    query point to fall INSIDE a MUNICIPALITY polygon with real geometry.
--    Confirmed live: only 2969 of Brazil's 5570 municipalities actually
--    have backfilled geometry (geo_areas, area_type='MUNICIPALITY',
--    geometry is not null) — just over half. A user in any of the other
--    ~2600 municipalities got zero news back regardless of whether real
--    G1 coverage existed for their actual state. Added a fallback: when
--    no polygon contains the point, use the state of the NEAREST
--    geometried municipality within 100km — generous enough to cover a
--    point just outside an ungeometried municipality's (missing) shape,
--    capped so a point genuinely outside Brazil never gets attributed to
--    a random "closest" Brazilian municipality.
--
-- 2. United Kingdom: BbcNewsAdapter (bbc_news.ts) is BeeAware's first UK
--    News Intelligence source, but geo_areas has ZERO rows for GB at all
--    (no UK equivalent of IBGE's municipality layer exists in this
--    project) — the original nearby_news could structurally never surface
--    it. Since BbcNewsAdapter's own events are already COUNTRY-precision
--    (see its header — no per-region signal exists in a BBC article URL
--    the way a G1 URL carries its state), a plain lat/lng bounding-box
--    check is enough: no false precision is being claimed either way.
--
-- country_code added to the return row so the client can tell "this is a
-- Brazilian state's news" from "this is UK-wide news" and label the
-- section honestly instead of assuming every row is a Brazilian state.
drop function if exists nearby_news(double precision, double precision, integer, integer);

create function nearby_news(
  point_lat double precision,
  point_lng double precision,
  max_results integer default 10,
  max_age_days integer default 30
)
returns table (
  id uuid,
  country_code text,
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
  resolved as (
    select coalesce(
      (
        select ga.state_code
        from geo_areas ga
        where ga.area_type = 'MUNICIPALITY'
          and ga.country_code = 'BR'
          and ST_Contains(ga.geometry, (select geom from pt))
        limit 1
      ),
      (
        select ga.state_code
        from geo_areas ga
        where ga.area_type = 'MUNICIPALITY'
          and ga.country_code = 'BR'
          and ST_DWithin(ga.geometry::geography, (select geom from pt)::geography, 100000)
        order by ga.geometry::geography <-> (select geom from pt)::geography
        limit 1
      )
    ) as br_state_code
  ),
  scope as (
    select
      br_state_code,
      br_state_code is null
        and point_lat between 49.85 and 60.9
        and point_lng between -8.65 and 1.77 as is_gb
    from resolved
  )
  select
    se.id,
    se.country_code,
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
  cross join scope
  left join security_sources ss on ss.id = se.source_id
  where se.source_type = 'news'
    and se.occurred_at >= (now() - (max_age_days || ' days')::interval)
    and (
      (se.country_code = 'BR' and se.state_code = scope.br_state_code)
      or (se.country_code = 'GB' and scope.is_gb)
    )
  order by se.occurred_at desc
  limit max_results;
$$;

grant execute on function nearby_news(double precision, double precision, integer, integer) to anon, authenticated;
