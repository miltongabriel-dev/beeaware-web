-- BeeAware Brasil roadmap / Phase 5 — Safety Pulse, Historical Safety RPC.
--
-- Modeled on municipality_crime_summary (20260824160000...sql) but adds
-- severity weighting and population normalization — the two things the
-- roadmap's own definition of Historical Safety (§1.2: "structural
-- baseline based mainly on official statistics, severity and population
-- normalisation") requires and municipality_crime_summary deliberately
-- doesn't do (it's a raw per-category sum, built for the choropleth).
--
-- Score is a RELATIVE percentile rank of each municipality's weighted
-- per-100k rate against every other rated municipality, inverted so a
-- lower rate -> a higher score (0-100, higher = safer relative to
-- current data). Deliberately not mapped onto an absolute/invented
-- threshold (e.g. "rate X = score 70") — there's no defensible source
-- for what an absolute cutoff should be, and picking one would be
-- exactly the kind of unevidenced number the roadmap's "evidence over
-- labels" principle warns against. A municipality with events but no
-- population (geo_areas.population not yet backfilled) is simply absent
-- from the result, not zero-filled or guessed.
create or replace function historical_safety(months_back integer default 12)
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
        else 2  -- unset severity: treat as medium rather than drop the row
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
    (100 - round(percent_rank() over (order by weighted_rate_per_100k) * 100))::integer as historical_safety_score,
    total_count
  from rated;
$$;

grant execute on function historical_safety(integer) to anon, authenticated;
