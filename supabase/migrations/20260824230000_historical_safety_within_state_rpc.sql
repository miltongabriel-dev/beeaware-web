-- BeeAware Brasil roadmap / Phase 5 — Safety Pulse, within-state
-- Historical Safety.
--
-- Companion to historical_safety() (now homicide-only, the honest
-- cross-state comparison — see 20260824220000...sql's header for why).
-- This one restores the broader severity-weighted VIOLENCE+PROPERTY+
-- PUBLIC_SAFETY view the first version of historical_safety() used, but
-- ranks municipalities only against OTHERS IN THE SAME STATE
-- (percent_rank() partitioned by state_code) rather than nationally.
-- That sidesteps the coverage-bias problem entirely: every municipality
-- in a given state comes from the same adapter, so they share the exact
-- same reporting scope — comparing Rio de Janeiro (the city) against
-- Niterói, both from RJ-ISP, is genuinely apples-to-apples in a way
-- comparing Rio against Belo Horizonte (a different source, different
-- scope) is not.
create or replace function historical_safety_within_state(months_back integer default 12)
returns table (
  city_ibge_code text,
  city_name text,
  state_code text,
  population integer,
  weighted_rate_per_100k numeric,
  historical_safety_score integer,
  total_count bigint
)
language sql
stable
as $$
  with weighted as (
    select
      ga.city_ibge_code,
      ga.name as city_name,
      ga.state_code,
      ga.population,
      sum(se.occurrence_count * case se.severity
        when 'high' then 3
        when 'medium' then 2
        when 'low' then 1
        else 2
      end) as weighted_sum,
      sum(se.occurrence_count) as total_count
    from geo_areas ga
    join security_events se
      on se.city_ibge_code = ga.city_ibge_code
     and se.country_code = ga.country_code
    where ga.area_type = 'MUNICIPALITY'
      and ga.population is not null
      and ga.population > 0
      and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY')
      and se.occurred_at >= (now() - (months_back || ' months')::interval)
    group by ga.city_ibge_code, ga.name, ga.state_code, ga.population
  ),
  rated as (
    select *, (weighted_sum::numeric / population) * 100000 as weighted_rate_per_100k
    from weighted
  )
  select
    city_ibge_code,
    city_name,
    state_code,
    population,
    weighted_rate_per_100k,
    (100 - round(percent_rank() over (partition by state_code order by weighted_rate_per_100k) * 100))::integer as historical_safety_score,
    total_count
  from rated;
$$;

grant execute on function historical_safety_within_state(integer) to anon, authenticated;
