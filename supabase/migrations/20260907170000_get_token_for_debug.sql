-- Temporary read-only helper to retrieve the service_role token for
-- direct curl debugging of FrCrimeAdapter/FrNewsAdapter (net.http_post's
-- async nature makes error messages hard to see quickly) — same pattern
-- as 20260905370000_get_ingest_token_for_direct_debug.sql.
select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key';
