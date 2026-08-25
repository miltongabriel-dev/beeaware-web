-- BeeAware Safety Pulse — single-municipality lookups for the Area
-- Intelligence screen (roadmap wireframe 9.2).
--
-- historical_safety_within_state() and recent_activity_within_state()
-- both return every municipality in the country in one call — reasonable
-- for a future national ranking view, wrong for "the user tapped one
-- municipality on the map, show its score": PostgREST caps rows at 1000
-- by default, and Brazil has 5,570 municipalities, so a naive client-side
-- fetch-then-filter would silently miss any municipality outside
-- whatever arbitrary first 1000 the server happens to return. These two
-- RPCs reuse the exact same scoring logic (still computed across the
-- full state partition server-side, so the percent_rank is real) and
-- filter down to the one requested city_ibge_code before returning.
create function historical_safety_for_city(
  target_city_ibge_code text,
  months_back integer default 12
)
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
  select *
  from historical_safety_within_state(months_back)
  where city_ibge_code = target_city_ibge_code;
$$;

grant execute on function historical_safety_for_city(text, integer) to anon, authenticated;

create function recent_activity_for_city(
  target_city_ibge_code text,
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
  select *
  from recent_activity_within_state(recent_days, baseline_months)
  where city_ibge_code = target_city_ibge_code;
$$;

grant execute on function recent_activity_for_city(text, integer, integer) to anon, authenticated;
