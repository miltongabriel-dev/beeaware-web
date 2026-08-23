-- BeeAware Global blueprint — Phase 0 hardening.
--
-- Closes two real gaps against release.new/BeeAware_Global_Product_Data_
-- Blueprint.pdf's canonical data model (see the plan this migration was
-- built from for the full gap analysis):
--
-- 1. raw_events: every adapter's fetch() already returns a uniform
--    RawSecurityRecord[] (sourceRecordId, payload, fetchedAt), but until
--    now it only ever lived in memory for the duration of one ingestion
--    run — nothing was persisted before normalize()'s transform
--    decisions. That means no replay, no way to re-derive a
--    normalized_events row if a mapping bug is found later, and no way
--    to diff "what did the source actually send us" against "what did
--    we do with it". payload is bytea (not jsonb) because several
--    adapters' raw payloads are binary archives (PRF/PA-SEGUP/RS-SSP all
--    fetch a zip/xlsx), not JSON — a uniform bytea column handles both
--    shapes; JSON-shaped payloads (IBGE, SINESP) get UTF-8-encoded into
--    it the same way. No public read policy: this is an internal/replay
--    store, not a product-facing table like security_events.
--
-- 2. security_sources.licence / security_events.iccs_code: schema hooks
--    for two blueprint fields with no real values to put in them yet —
--    licence needs a real per-source terms review (the blueprint's own
--    closing line: "not a legal determination... validate source-
--    specific terms... before production use"), and iccs_code needs the
--    actual UNODC ICCS classification document, which wasn't reliably
--    fetchable while writing this migration (the expected PDF URL
--    404'd). Added as nullable columns now rather than deferred
--    entirely, so populating them later is a data-fill, not a schema
--    change.

create table raw_events (
  id uuid primary key default gen_random_uuid(),
  source_id uuid references security_sources (id),
  source_record_id text not null,
  payload bytea not null,
  checksum text not null,
  adapter_name text not null,
  ingested_at timestamptz not null default now()
);

create index raw_events_source_record_idx on raw_events (source_id, source_record_id);
create index raw_events_adapter_name_idx on raw_events (adapter_name);

alter table raw_events enable row level security;
-- No policies: internal/replay use only (service_role bypasses RLS
-- entirely, same as every write path in this schema already relies on).

alter table security_sources add column licence text;
alter table security_events add column iccs_code text;
