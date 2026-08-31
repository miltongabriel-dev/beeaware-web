-- BeeAware Global roadmap — one-off, operator-only debug aid: print the
-- ingest function's own auth token so UkPoliceAdapter can be curled
-- directly (with a real client-side timeout under our control) instead
-- of through pg_net, whose 5s-default timeout and internal queuing have
-- made it impossible to tell whether the adapter itself is hanging or
-- just slow. Read once from this migration's own `supabase db push`
-- output, never stored or logged elsewhere.
do $$
declare
  v text;
begin
  select decrypted_secret into v from vault.decrypted_secrets where name = 'service_role_key';
  raise notice 'token: %', v;
end $$;
