-- One-off read-only diagnostic: Supabase flagged a public table with RLS
-- disabled (security advisory, 2026-08-31). Confirm exactly which
-- public tables have rowsecurity off before fixing anything.
do $$
declare
  r record;
begin
  for r in
    select c.relname, c.relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
    order by c.relrowsecurity, c.relname
  loop
    raise notice 'table=% rls_enabled=%', r.relname, r.relrowsecurity;
  end loop;
end $$;
