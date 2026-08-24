-- BeeAware map time-window fix.
--
-- nearby_security_events (the RPC behind BrazilSecurityApi.fetchForArea,
-- currently the app's only source of PRF/security_events map pins) had
-- no date filter at all — an accident from years ago could keep showing
-- on the map indefinitely, and could even crowd out recent ones under
-- max_results' nearest-first ordering. The map is meant to show recent,
-- actionable data (same reasoning as the incidents-table cutoff added
-- alongside this migration in IncidentApi.fetchVisibleIncidents);
-- longer-window historical queries (e.g. municipality_crime_summary for
-- the regional choropleth) are unaffected — they already have their own
-- separate months_back window.
--
-- Adds max_age_days (default 60, ~2 months) rather than hardcoding the
-- cutoff, so a future caller (e.g. an "older reports" toggle) can widen
-- it without another migration. Changing the parameter list means
-- CREATE OR REPLACE can't reuse the old signature in place — drop the
-- old 4-arg overload first so callers can't ambiguously resolve to
-- either one.
drop function if exists nearby_security_events(double precision, double precision, double precision, integer);

create function nearby_security_events(
  center_lat double precision,
  center_lng double precision,
  radius_meters double precision,
  max_results integer default 300,
  max_age_days integer default 60
)
returns setof security_events
language sql
stable
as $$
  select *
  from security_events
  where location is not null
    and geo_precision in ('EXACT', 'STREET')
    and occurred_at >= (now() - (max_age_days || ' days')::interval)
    and ST_DWithin(
      location::geography,
      ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography,
      radius_meters
    )
  order by location::geography <-> ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography
  limit max_results;
$$;

grant execute on function nearby_security_events(double precision, double precision, double precision, integer, integer)
  to anon, authenticated;
