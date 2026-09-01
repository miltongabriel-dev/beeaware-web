-- One-off read-only diagnostic (no schema change) to size up the
-- data-retention/compaction question raised after the UK choropleth work:
-- how big are security_events and raw_events actually getting, and how
-- much of that is "old" vs. within a 6-12 month window. Kept in migration
-- history per this repo's established precedent (see the UK ingestion
-- debugging chain, 20260831160000-230000) rather than deleted after use.
do $$
declare
  r record;
begin
  raise notice '--- table sizes (total, incl. indexes) ---';
  for r in
    select relname,
           pg_size_pretty(pg_total_relation_size(oid)) as total_size,
           pg_size_pretty(pg_relation_size(oid)) as table_size
    from pg_class
    where relname in ('security_events', 'raw_events', 'geo_areas', 'incidents')
      and relkind = 'r'
    order by pg_total_relation_size(oid) desc
  loop
    raise notice '%: total=% table_only=%', r.relname, r.total_size, r.table_size;
  end loop;

  raise notice '--- security_events ---';
  for r in
    select count(*) as n,
           min(occurred_at) as oldest,
           max(occurred_at) as newest,
           count(*) filter (where occurred_at < now() - interval '6 months') as older_than_6mo,
           count(*) filter (where occurred_at < now() - interval '12 months') as older_than_12mo
    from security_events
  loop
    raise notice 'rows=% oldest=% newest=% older_than_6mo=% older_than_12mo=%',
      r.n, r.oldest, r.newest, r.older_than_6mo, r.older_than_12mo;
  end loop;

  raise notice '--- security_events by month ---';
  for r in
    select to_char(date_trunc('month', occurred_at), 'YYYY-MM') as ym, count(*) as n
    from security_events
    group by 1
    order by 1 desc
    limit 18
  loop
    raise notice '%: %', r.ym, r.n;
  end loop;

  raise notice '--- raw_events ---';
  for r in
    select count(*) as n,
           min(ingested_at) as oldest,
           max(ingested_at) as newest,
           count(*) filter (where ingested_at < now() - interval '6 months') as older_than_6mo,
           pg_size_pretty(coalesce(sum(length(payload)), 0)) as payload_bytes_sum
    from raw_events
  loop
    raise notice 'rows=% oldest=% newest=% older_than_6mo=% payload_bytes_sum=%',
      r.n, r.oldest, r.newest, r.older_than_6mo, r.payload_bytes_sum;
  end loop;

  raise notice '--- raw_events by month ---';
  for r in
    select to_char(date_trunc('month', ingested_at), 'YYYY-MM') as ym, count(*) as n
    from raw_events
    group by 1
    order by 1 desc
    limit 18
  loop
    raise notice '%: %', r.ym, r.n;
  end loop;

  raise notice '--- database size ---';
  for r in select pg_size_pretty(pg_database_size(current_database())) as db_size loop
    raise notice 'database_size=%', r.db_size;
  end loop;
end $$;
