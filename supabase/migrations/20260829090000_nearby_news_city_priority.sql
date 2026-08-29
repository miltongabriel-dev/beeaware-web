-- BeeAware Brasil roadmap — nearby_news: city-level priority.
--
-- G1NewsAdapter (g1_news.ts, this same date) now tags a MUNICIPALITY-
-- precision city on articles whose text names a real municipality from
-- the article's own UF, falling back to STATE precision exactly as
-- before when it can't. This migration is the read side of that: resolve
-- the caller's own city_ibge_code the same way this function already
-- resolves their state_code (via the containing/nearest MUNICIPALITY
-- geo_areas lookup), and rank a news row whose city_ibge_code matches
-- ahead of the rest of the state's news — never FILTER by it, since most
-- articles still only carry STATE precision and dropping them would
-- shrink the feed rather than just re-order it. This is exactly the
-- fallback chain asked for: city when identifiable, otherwise the
-- region's news is still shown, same as before.
drop function if exists nearby_news(double precision, double precision, integer, integer, text);

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
  city text,
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
  containing as (
    select ga.state_code, ga.city_ibge_code
    from geo_areas ga
    where ga.area_type = 'MUNICIPALITY'
      and ga.country_code = 'BR'
      and ST_Contains(ga.geometry, (select geom from pt))
    limit 1
  ),
  nearest as (
    select ga.state_code, ga.city_ibge_code
    from geo_areas ga
    where ga.area_type = 'MUNICIPALITY'
      and ga.country_code = 'BR'
      and ST_DWithin(ga.geometry::geography, (select geom from pt)::geography, 100000)
    order by ga.geometry::geography <-> (select geom from pt)::geography
    limit 1
  ),
  resolved as (
    select
      coalesce(
        (select state_code from containing),
        (select state_code from nearest),
        state_code_hint
      ) as br_state_code,
      coalesce(
        (select city_ibge_code from containing),
        (select city_ibge_code from nearest)
      ) as br_city_ibge_code
  ),
  scope as (
    select
      br_state_code,
      br_city_ibge_code,
      br_state_code is null
        and point_lat between 49.85 and 60.9
        and point_lng between -8.65 and 1.77 as is_gb
    from resolved
  )
  select
    se.id,
    se.country_code,
    se.state_code,
    se.city,
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
  order by
    -- coalesce(..., false) matters here, not just style: se.city_ibge_code
    -- is null for most rows (STATE-precision news, the common case), and
    -- `null = scope.br_city_ibge_code` evaluates to NULL, not false, under
    -- three-valued SQL logic. Postgres's DESC default is NULLS FIRST, so
    -- without this coalesce every STATE-only row's NULL would sort ahead
    -- of a real TRUE city match — the exact opposite of the intended
    -- priority (confirmed live: without it, Guarujá/Juiz de Fora matches
    -- sank behind every unmatched row instead of floating above them).
    coalesce(scope.br_city_ibge_code is not null and se.city_ibge_code = scope.br_city_ibge_code, false) desc,
    se.occurred_at desc
  limit max_results;
$$;

grant execute on function nearby_news(double precision, double precision, integer, integer, text) to anon, authenticated;
