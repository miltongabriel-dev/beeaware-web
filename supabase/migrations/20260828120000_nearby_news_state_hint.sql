-- BeeAware Global blueprint — nearby_news: authoritative state hint.
--
-- The nearest-geometried-municipality fallback added in
-- 20260828110000 still can't help a state that has ZERO backfilled
-- municipality geometry at all — confirmed live: Rondônia (RO) has none,
-- despite having a real, current G1NewsAdapter article. No amount of
-- widening the search radius fixes that; the nearest geometried
-- municipality to any point in RO is simply in a different state, and
-- "widen until something matches" would start misattributing news across
-- state lines for exactly the state that needs it most.
--
-- The client already solves this same problem for its location label
-- (reverseGeocode in geocoding.dart calls Nominatim, which knows every
-- Brazilian state regardless of BeeAware's own geometry backfill status)
-- — state_code_hint lets it pass that answer straight through as a last
-- resort, used only when neither polygon containment nor the
-- nearest-municipality fallback resolved anything. Kept as a fallback
-- rather than the primary path so a stale/wrong hint can never override
-- this project's own more precise geometry when that geometry exists.
drop function if exists nearby_news(double precision, double precision, integer, integer);

create function nearby_news(
  point_lat double precision,
  point_lng double precision,
  max_results integer default 10,
  max_age_days integer default 30,
  state_code_hint text default null
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
      ),
      state_code_hint
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

grant execute on function nearby_news(double precision, double precision, integer, integer, text) to anon, authenticated;
