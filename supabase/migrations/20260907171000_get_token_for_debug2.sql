-- Follow-up to 20260907170000 — that one was a bare select (no output in
-- `supabase db push` logs); this actually surfaces it via raise notice,
-- same pattern as 20260905370000_get_ingest_token_for_direct_debug.sql.
do $$
declare
  tok text;
begin
  select decrypted_secret into tok from vault.decrypted_secrets where name = 'service_role_key';
  raise notice 'token: %', tok;
end $$;
