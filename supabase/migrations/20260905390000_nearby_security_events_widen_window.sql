-- BeeAware Global roadmap — widen nearby_security_events' default
-- max_age_days (60 -> 90).
--
-- Root-caused live (2026-09-01), the same class of bug as
-- 20260904110000's police_force_crime_summary window fix: MadridAccidents
-- Adapter's own source lags by design (its rolling-monthly CSV only
-- reached 30 June 2026 as of "now" = 2026-09-01) — a real ~2-month gap
-- that sat right at the edge of the previous 60-day cutoff, so all
-- 11,518 real accidents just ingested returned ZERO rows from
-- nearby_security_events (confirmed live: 0 results within 5km of
-- central Madrid, despite the data being there with real EXACT
-- coordinates). Brazil's own official sources (PRF etc.) report much
-- more recent data, so widening to 90 days doesn't make Brazil's pins
-- meaningfully less "recent" while giving Madrid's own real cadence
-- (~2 months lag + up to a week between cron runs) genuine headroom —
-- same reasoning as the 6-month choropleth windows already in place.
-- BrazilSecurityApi.dart's own default must change to match (it always
-- passes max_age_days explicitly, so this SQL default alone doesn't
-- reach the app).
create or replace function nearby_security_events(
  center_lat double precision,
  center_lng double precision,
  radius_meters double precision,
  max_results integer default 300,
  max_age_days integer default 90
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
