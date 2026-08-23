-- BeeAware Global blueprint — Phase 1 part 2: travel advisories.
--
-- A distinct entity from security_events, per the blueprint's own canonical
-- data model (§4): issuer, level, text summary, effective_at — no
-- occurrence-count/severity shape, and its own API surface
-- (GET /v1/advisories) separate from GET /v1/sources/coverage. Current-state
-- table (one row per source+country, upserted), same as security_sources
-- itself — full history is already covered generically by raw_events
-- (Phase 0), no separate history table needed here.
create table travel_advisories (
  id uuid primary key default gen_random_uuid(),
  source_id uuid references security_sources (id),
  country_code text not null,
  country_slug text not null,
  issuer text not null,
  level text not null,
  raw_alert_status jsonb not null default '[]'::jsonb,
  summary text,
  source_url text,
  effective_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table travel_advisories
  add constraint travel_advisories_source_country_key
  unique (source_id, country_code);

create index travel_advisories_country_code_idx on travel_advisories (country_code);

create trigger travel_advisories_set_updated_at
  before update on travel_advisories
  for each row execute function set_updated_at();

-- Public government data, no PII — same treatment as security_events.
alter table travel_advisories enable row level security;

create policy "Public read travel advisories" on travel_advisories
  for select using (true);
