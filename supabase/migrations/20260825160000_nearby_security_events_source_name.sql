-- BeeAware map source-attribution fix.
--
-- nearby_security_events (behind BrazilSecurityApi.fetchForArea) returned
-- setof security_events with no way to tell which of the now-11 Brazil
-- adapters produced a given row, so the Flutter client hardcoded every
-- pin's source as "PRF" — true back when PRF was the only point-precision
-- adapter, wrong since RjIspAdapter/RsSspAdapter/BaAdapter/AlAdapter/
-- MtAdapter/EsSespAdapter/MgAdapter/SpVehicleAdapter/PaSegupAdapter/
-- RenaestAdapter all started feeding this same table. That's why every
-- Brazil incident card in the app said "Fonte: PRF", including RJ
-- homicide reports and RS/BA/AL... occurrences that have nothing to do
-- with PRF.
--
-- Joins security_sources for its `organisation` column (the real-world
-- name each adapter already registers itself under, e.g. "Instituto de
-- Segurança Pública do Rio de Janeiro") rather than adapter_name (an
-- internal class name never meant for display). Adding a column changes
-- the return type, so the old signature must be dropped first, same as
-- 20260824150000's max_age_days change.
drop function if exists nearby_security_events(double precision, double precision, double precision, integer, integer);

create function nearby_security_events(
  center_lat double precision,
  center_lng double precision,
  radius_meters double precision,
  max_results integer default 300,
  max_age_days integer default 60
)
returns table (
  id uuid,
  country_code text,
  state_code text,
  city_ibge_code text,
  source_id uuid,
  source_record_id text,
  source_type text,
  event_category security_event_category,
  event_type text,
  event_subtype text,
  original_category text,
  occurred_at timestamptz,
  reported_at timestamptz,
  published_at timestamptz,
  location geometry(Point, 4326),
  geo_precision geo_precision,
  location_confidence numeric(3, 2),
  neighborhood text,
  district text,
  city text,
  state text,
  occurrence_count integer,
  victim_count integer,
  severity text,
  confidence_score numeric(4, 3),
  canonical_event_id uuid,
  raw_payload jsonb,
  created_at timestamptz,
  updated_at timestamptz,
  source_organisation text
)
language sql
stable
as $$
  select
    se.id, se.country_code, se.state_code, se.city_ibge_code, se.source_id,
    se.source_record_id, se.source_type, se.event_category, se.event_type,
    se.event_subtype, se.original_category, se.occurred_at, se.reported_at,
    se.published_at, se.location, se.geo_precision, se.location_confidence,
    se.neighborhood, se.district, se.city, se.state, se.occurrence_count,
    se.victim_count, se.severity, se.confidence_score, se.canonical_event_id,
    se.raw_payload, se.created_at, se.updated_at,
    ss.organisation as source_organisation
  from security_events se
  left join security_sources ss on ss.id = se.source_id
  where se.location is not null
    and se.geo_precision in ('EXACT', 'STREET')
    and se.occurred_at >= (now() - (max_age_days || ' days')::interval)
    and ST_DWithin(
      se.location::geography,
      ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography,
      radius_meters
    )
  order by se.location::geography <-> ST_SetSRID(ST_MakePoint(center_lng, center_lat), 4326)::geography
  limit max_results;
$$;

grant execute on function nearby_security_events(double precision, double precision, double precision, integer, integer)
  to anon, authenticated;
