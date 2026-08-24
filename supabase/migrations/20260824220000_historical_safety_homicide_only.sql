-- BeeAware Brasil roadmap / Phase 5 — Safety Pulse, fix cross-state
-- coverage bias in historical_safety().
--
-- Validating the first version against real data (querying real capitals
-- with a user) surfaced a genuine problem: Rio de Janeiro scored 0
-- (worst) with 255,958 weighted VIOLENCE+PROPERTY+PUBLIC_SAFETY events
-- over 12 months against Belo Horizonte's 971 and Alagoas' 263 — not
-- because Rio is ~263x more dangerous than Belo Horizonte, but because
-- RJ-ISP reports comprehensively (theft, robbery, every property crime)
-- while MG-SSP reports a narrower violent-crime list and AL-SEDS reports
-- only CVLI (lethal violent crime). Confirmed via the new
-- event_type_coverage() RPC: of the 6 states with any VIOLENCE data at
-- all (AL, ES, MG, PA, RJ, RS), 'homicide' is the ONLY event_type every
-- one of them reports — femicide is missing from PA/RS, sexual_violence
-- missing from AL/ES, everything else is even narrower. Comparing a
-- comprehensive source against a homicide-only source under any shared
-- category set inflates the comprehensive source's apparent danger for
-- reasons that have nothing to do with real safety — exactly the
-- "coverage bias" the roadmap's release gate names.
--
-- Fix: restrict the cross-state comparison to homicide only — the true
-- common denominator. Severity weighting is dropped too: it's now
-- moot (every source tags homicide "high" in practice, and percent_rank
-- is invariant to multiplying every row by the same constant anyway) and
-- was adding complexity with no remaining effect. Column renamed from
-- weighted_rate_per_100k to homicide_rate_per_100k to describe what it
-- actually is now, not what it used to be.
--
-- This is the CROSS-STATE (national) comparison. A second RPC,
-- historical_safety_within_state(), covers the broader per-state
-- category set for comparing municipalities against others in the same
-- state, where the same source's scope applies uniformly and this bias
-- doesn't arise.
-- Changing a returned column's name (weighted_rate_per_100k ->
-- homicide_rate_per_100k) changes the function's OUT-parameter row
-- type, which CREATE OR REPLACE can't do in place — drop first.
drop function if exists historical_safety(integer);

create function historical_safety(months_back integer default 12)
returns table (
  city_ibge_code text,
  city_name text,
  state_code text,
  population integer,
  homicide_rate_per_100k numeric,
  historical_safety_score integer,
  total_count bigint
)
language sql
stable
as $$
  with counted as (
    select
      ga.city_ibge_code,
      ga.name as city_name,
      ga.state_code,
      ga.population,
      sum(se.occurrence_count) as total_count
    from geo_areas ga
    join security_events se
      on se.city_ibge_code = ga.city_ibge_code
     and se.country_code = ga.country_code
    where ga.area_type = 'MUNICIPALITY'
      and ga.population is not null
      and ga.population > 0
      and se.event_type = 'homicide'
      and se.occurred_at >= (now() - (months_back || ' months')::interval)
    group by ga.city_ibge_code, ga.name, ga.state_code, ga.population
  ),
  rated as (
    select *, (total_count::numeric / population) * 100000 as homicide_rate_per_100k
    from counted
  )
  select
    city_ibge_code,
    city_name,
    state_code,
    population,
    homicide_rate_per_100k,
    (100 - round(percent_rank() over (order by homicide_rate_per_100k) * 100))::integer as historical_safety_score,
    total_count
  from rated;
$$;

grant execute on function historical_safety(integer) to anon, authenticated;
