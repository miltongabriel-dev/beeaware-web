-- One-off diagnostic: inspect net.http_post's actual signature to find
-- the correct parameter name for a longer timeout (20260905330000's
-- attempt using timeout_milliseconds failed to apply).
do $$
declare
  r record;
begin
  for r in
    select p.proname, pg_get_function_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'net' and p.proname = 'http_post'
  loop
    raise notice '%(%)', r.proname, r.args;
  end loop;
end $$;
