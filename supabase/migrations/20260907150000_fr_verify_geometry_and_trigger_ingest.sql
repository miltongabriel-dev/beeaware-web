-- Verify the 101 French département geometries landed correctly, then
-- manually trigger FrCrimeAdapter and FrNewsAdapter for the historical/
-- reproducible record (same net.http_post + vault service_role_key
-- pattern used throughout this project's migration history).
do $$
declare
  n int;
begin
  select count(*) into n from geo_areas where country_code = 'FR' and area_type = 'DEPARTEMENT';
  raise notice 'FR DEPARTEMENT rows in geo_areas: %', n;
end $$;

select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('adapter', 'FrCrimeAdapter')
);

select net.http_post(
  url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
    'Content-Type', 'application/json'
  ),
  body := jsonb_build_object('adapter', 'FrNewsAdapter')
);
