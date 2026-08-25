-- BeeAware Brasil roadmap / Phase 5 — Safety Pulse, Recent Activity.
--
-- Second of the three Safety Pulse dimensions (roadmap 1.2): "Detect
-- recent changes versus the historical baseline". Historical Safety
-- (20260824190000/20260824220000/20260824230000) already answers "how
-- does this place compare to others" — this answers a different
-- question, "is this place busier than its OWN normal right now",
-- which sidesteps the cross-adapter coverage-bias problem entirely:
-- comparing a municipality's own recent window to its own trailing
-- baseline never mixes two different adapters' reporting scopes the way
-- comparing two different municipalities can.
--
-- Same score direction and shape as historical_safety_within_state for
-- consistency: 100 - percent_rank() * 100, partitioned by state_code
-- (same reporting-scope-sharing argument — every municipality in one
-- state comes from the same adapter), so a low score means "recent
-- activity increased more than peers in this state", not an absolute
-- probability. Ranked WITHIN state only, same reasoning as
-- historical_safety_within_state's header.
--
-- baseline_rate_per_100k_equivalent scales the trailing-baseline rate
-- (measured over baseline_months, EXCLUDING the recent_days window
-- itself so a real recent spike isn't diluted into its own baseline) to
-- the same day-count as recent_days, so the two rates are directly
-- comparable rather than comparing a 30-day count to a 335-day count.
-- change_ratio is recent-over-baseline: 1.0 = no change, 2.0 = doubled,
-- 0.5 = halved. NULL baseline (no prior activity at all) is excluded
-- rather than treated as an infinite/undefined ratio.
--
-- No event-count floor is applied here, same as historical_safety_within_state
-- — a municipality with very few events produces a noisy ratio, but that's
-- surfaced via total_count/baseline_count for the caller to judge, not
-- hidden by an arbitrary threshold picked without real usage data.
create function recent_activity_within_state(
  recent_days integer default 30,
  baseline_months integer default 12
)
returns table (
  city_ibge_code text,
  city_name text,
  state_code text,
  population integer,
  recent_count bigint,
  recent_rate_per_100k numeric,
  baseline_count bigint,
  baseline_rate_per_100k_equivalent numeric,
  change_ratio numeric,
  recent_activity_score integer
)
language sql
stable
as $$
  with recent as (
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
      end) as weighted_recent,
      sum(se.occurrence_count) as recent_count
    from geo_areas ga
    join security_events se
      on se.city_ibge_code = ga.city_ibge_code
     and se.country_code = ga.country_code
    where ga.area_type = 'MUNICIPALITY'
      and ga.population is not null
      and ga.population > 0
      and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY')
      and se.occurred_at >= (now() - (recent_days || ' days')::interval)
    group by ga.city_ibge_code, ga.name, ga.state_code, ga.population
  ),
  baseline as (
    select
      ga.city_ibge_code,
      sum(se.occurrence_count * case se.severity
        when 'high' then 3
        when 'medium' then 2
        when 'low' then 1
        else 2
      end) as weighted_baseline,
      sum(se.occurrence_count) as baseline_count
    from geo_areas ga
    join security_events se
      on se.city_ibge_code = ga.city_ibge_code
     and se.country_code = ga.country_code
    where ga.area_type = 'MUNICIPALITY'
      and se.event_category in ('VIOLENCE', 'PROPERTY', 'PUBLIC_SAFETY')
      and se.occurred_at >= (now() - (baseline_months || ' months')::interval)
      and se.occurred_at < (now() - (recent_days || ' days')::interval)
    group by ga.city_ibge_code
  ),
  combined as (
    select
      r.city_ibge_code,
      r.city_name,
      r.state_code,
      r.population,
      r.recent_count,
      (r.weighted_recent::numeric / r.population) * 100000 as recent_rate_per_100k,
      coalesce(b.baseline_count, 0) as baseline_count,
      case
        when b.weighted_baseline is null or b.weighted_baseline = 0 then null
        else (b.weighted_baseline::numeric
                / greatest(baseline_months * 30 - recent_days, 1) * recent_days
                / r.population) * 100000
      end as baseline_rate_per_100k_equivalent
    from recent r
    left join baseline b on b.city_ibge_code = r.city_ibge_code
  ),
  rated as (
    select
      *,
      case
        when baseline_rate_per_100k_equivalent is null or baseline_rate_per_100k_equivalent = 0 then null
        else recent_rate_per_100k / baseline_rate_per_100k_equivalent
      end as change_ratio
    from combined
  ),
  -- percent_rank() computed only over rows with a real change_ratio —
  -- including the null-ratio rows in the same window would still count
  -- them toward every other row's rank denominator (nulls sort last,
  -- they don't drop out on their own), silently skewing every real score
  -- in a partition that has any unrated municipality in it.
  scored as (
    select
      city_ibge_code,
      (100 - round(percent_rank() over (
        partition by state_code
        order by change_ratio
      ) * 100))::integer as recent_activity_score
    from rated
    where change_ratio is not null
  )
  select
    rated.city_ibge_code,
    rated.city_name,
    rated.state_code,
    rated.population,
    rated.recent_count,
    rated.recent_rate_per_100k,
    rated.baseline_count,
    rated.baseline_rate_per_100k_equivalent,
    rated.change_ratio,
    scored.recent_activity_score
  from rated
  left join scored on scored.city_ibge_code = rated.city_ibge_code;
$$;

grant execute on function recent_activity_within_state(integer, integer) to anon, authenticated;
