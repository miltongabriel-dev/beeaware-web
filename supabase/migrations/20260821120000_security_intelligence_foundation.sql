-- BeeAware Brasil roadmap — Phase 0: foundation schema.
--
-- Adds a country-aware "security intelligence" layer (security_sources,
-- geo_areas, security_events) alongside the existing `incidents` table.
-- `incidents` is untouched — the UK app keeps working exactly as it does
-- today. This new layer is additive; nothing reads or writes it yet.
--
-- Reference: release.new/BeeAware_Brasil_Product_Data_Engineering_Roadmap.pdf
-- sections 2, 6, 7 and 11.1 (Phase 0 Go/No-Go: the schema must accept UK
-- and Brazil data without country-specific columns or client-side
-- special cases).

create extension if not exists postgis;
create extension if not exists pgcrypto;

-- ===== Taxonomy (section 6.1) =====
-- Top-level category is a closed set; event_type/event_subtype stay as
-- text because adapters own that mapping (roadmap 2.1) and the set grows
-- with every new state source — a DB enum would mean a migration per
-- adapter.
create type security_event_category as enum (
  'VIOLENCE',
  'PROPERTY',
  'PUBLIC_SAFETY',
  'ROAD_SAFETY',
  'COMMUNITY'
);

-- Geographic precision (section 7.2) — controls display behaviour on the
-- client: NEIGHBORHOOD and coarser must never be rendered as an exact pin.
create type geo_precision as enum (
  'EXACT',
  'STREET',
  'NEIGHBORHOOD',
  'DISTRICT',
  'MUNICIPALITY',
  'STATE'
);

create type geo_area_type as enum (
  'COUNTRY',
  'STATE',
  'MUNICIPALITY',
  'NEIGHBORHOOD',
  'RISP',
  'AISP',
  'CISP',
  'AIS',
  'RA'
);

create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ===== security_sources (section 6.3) =====
-- Registry of every feed BeeAware ingests — official, news or community —
-- one row per adapter instance. Adapters update last_check/last_success
-- themselves; this table is what a future "source health dashboard"
-- (roadmap 12.5) reads from.
create table security_sources (
  id uuid primary key default gen_random_uuid(),
  country_code text not null,
  state_code text,
  name text not null,
  organisation text,
  source_type text not null check (source_type in ('official', 'community', 'news')),
  source_url text,
  adapter_name text,
  adapter_version text,
  refresh_frequency text,
  last_check timestamptz,
  last_success timestamptz,
  last_data_date date,
  geo_precision geo_precision,
  reliability_score numeric(3, 2),
  quality_score numeric(3, 2),
  terms_reviewed_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger security_sources_set_updated_at
  before update on security_sources
  for each row execute function set_updated_at();

create index security_sources_country_state_idx
  on security_sources (country_code, state_code);

-- ===== geo_areas (section 6.4) =====
-- Official territorial polygons — municipalities, neighbourhoods, and
-- state-specific security-area hierarchies (RISP/AISP/CISP for Rio,
-- roadmap 4.3). geometry is untyped (not just Polygon) because this table
-- also has to hold municipality/state boundaries, which some sources
-- publish as MultiPolygon.
create table geo_areas (
  id uuid primary key default gen_random_uuid(),
  country_code text not null,
  state_code text,
  city_ibge_code text,
  area_type geo_area_type not null,
  name text not null,
  geometry geometry(Geometry, 4326) not null,
  parent_area_id uuid references geo_areas (id),
  source text,
  source_version text,
  valid_from date not null default current_date,
  valid_to date,
  created_at timestamptz not null default now()
);

create index geo_areas_geometry_idx on geo_areas using gist (geometry);
create index geo_areas_country_state_idx on geo_areas (country_code, state_code);
create index geo_areas_city_ibge_code_idx on geo_areas (city_ibge_code);
create index geo_areas_parent_area_id_idx on geo_areas (parent_area_id);

-- ===== security_events (section 6.2) =====
-- The canonical event table for the new intelligence layer — official
-- statistics, news-derived incidents and community reports all normalise
-- into this shape. canonical_event_id lets the future deduplication
-- engine (roadmap 7.4) point several source records at one real-world
-- event without deleting any of them.
create table security_events (
  id uuid primary key default gen_random_uuid(),
  country_code text not null,
  state_code text,
  city_ibge_code text,
  source_id uuid references security_sources (id),
  source_record_id text,
  source_type text not null check (source_type in ('official', 'community', 'news')),
  event_category security_event_category not null,
  event_type text not null,
  event_subtype text,
  original_category text,
  occurred_at timestamptz,
  reported_at timestamptz,
  published_at timestamptz,
  location geometry(Point, 4326),
  geo_precision geo_precision not null default 'MUNICIPALITY',
  location_confidence numeric(3, 2),
  neighborhood text,
  district text,
  city text,
  state text,
  occurrence_count integer not null default 1,
  victim_count integer,
  severity text,
  confidence_score numeric(4, 3),
  canonical_event_id uuid references security_events (id),
  raw_payload jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger security_events_set_updated_at
  before update on security_events
  for each row execute function set_updated_at();

create index security_events_location_idx on security_events using gist (location);
create index security_events_country_state_city_idx
  on security_events (country_code, state_code, city_ibge_code);
create index security_events_occurred_at_idx on security_events (occurred_at desc);
create index security_events_canonical_event_id_idx on security_events (canonical_event_id);
create index security_events_source_id_idx on security_events (source_id);

-- ===== Row level security =====
-- This layer is adapter-populated, not user-submitted (community reports
-- from the app still go through the existing `incidents` table) — so
-- public read, no public write. Edge Functions write with the
-- service_role key, which bypasses RLS entirely.
alter table security_sources enable row level security;
alter table geo_areas enable row level security;
alter table security_events enable row level security;

create policy "Public read active sources" on security_sources
  for select using (active = true);

create policy "Public read geo areas" on geo_areas
  for select using (true);

create policy "Public read security events" on security_events
  for select using (true);
