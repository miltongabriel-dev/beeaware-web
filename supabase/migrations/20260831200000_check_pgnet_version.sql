do $$
declare
  v text;
begin
  select extversion into v from pg_extension where extname = 'pg_net';
  raise notice 'pg_net version: %', v;
end $$;
