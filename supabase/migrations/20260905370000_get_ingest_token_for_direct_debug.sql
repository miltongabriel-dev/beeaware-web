-- One-off: surface the ingest function's own auth token (stored in
-- vault under the name 'service_role_key' per 20260821140000's own
-- comment — a dedicated token for this endpoint, not the real Supabase
-- service_role key) so it can be used to curl the deployed function
-- directly from outside pg_net, which has been unreliable for
-- diagnosing MadridAccidentsAdapter's real behaviour (its own worker
-- never produced a response for request id 318 even with an explicit
-- 120s timeout).
do $$
declare
  tok text;
begin
  select decrypted_secret into tok from vault.decrypted_secrets where name = 'service_role_key';
  raise notice 'token: %', tok;
end $$;
