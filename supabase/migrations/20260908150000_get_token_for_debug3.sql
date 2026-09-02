-- Temporary read-only helper to retrieve the service_role token for
-- direct curl debugging of DeCrimeAdapter/DeNewsAdapter — same pattern
-- as 20260907171000_get_token_for_debug2.sql.
do $$
declare
  tok text;
begin
  select decrypted_secret into tok from vault.decrypted_secrets where name = 'service_role_key';
  raise notice 'token: %', tok;
end $$;
