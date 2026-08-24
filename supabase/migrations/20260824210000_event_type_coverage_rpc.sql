-- BeeAware Brasil roadmap / Phase 5 — Safety Pulse coverage-bias audit.
--
-- Built to answer a concrete question while validating historical_safety
-- for real: which event_types does each state's adapter actually report?
-- Comparing Rio (255,958 events/12mo, RJ-ISP reports everything) against
-- Belo Horizonte (971 events/12mo, MG-SSP reports a narrower violent-
-- crime list) or Alagoas (263 events/12mo, AL-SEDS is lethal-violence-
-- only) at the same percentile rank made RJ look far more dangerous
-- purely because its source has broader scope, not because its real
-- rate is worse — exactly the "coverage bias" the roadmap's release gate
-- names. Kept as a real, reusable observability RPC (matches the
-- roadmap's own Data Quality Engine / Source Health Dashboard concept,
-- §12.4-12.5) rather than a one-off throwaway query.
create or replace function event_type_coverage(months_back integer default 12)
returns table (
  state_code text,
  event_category security_event_category,
  event_type text,
  occurrence_count bigint
)
language sql
stable
as $$
  select
    state_code,
    event_category,
    event_type,
    sum(occurrence_count) as occurrence_count
  from security_events
  where occurred_at >= (now() - (months_back || ' months')::interval)
  group by state_code, event_category, event_type
  order by state_code, event_category, event_type;
$$;

grant execute on function event_type_coverage(integer) to anon, authenticated;
