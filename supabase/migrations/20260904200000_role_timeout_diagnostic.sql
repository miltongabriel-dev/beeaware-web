-- One-off read-only diagnostic: check the statement_timeout actually
-- configured for the anon/authenticated roles PostgREST uses (the
-- migration/CLI connection runs as a different role with a 2-minute
-- timeout, per 20260904180000 -- that's not what the live app hits).
do $$
declare
  r record;
begin
  for r in
    select rolname, rolconfig
    from pg_roles
    where rolname in ('anon', 'authenticated', 'service_role', 'postgres', 'authenticator')
  loop
    raise notice 'role=% rolconfig=%', r.rolname, r.rolconfig;
  end loop;
end $$;
