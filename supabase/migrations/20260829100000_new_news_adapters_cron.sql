-- BeeAware Brasil roadmap — News Intelligence expansion schedulers.
--
-- Same 4-hourly cadence and idempotency reasoning as G1NewsAdapter/
-- BbcNewsAdapter's own crons (news values recency, and every adapter's
-- sourceRecordId is a real per-article guid/link, so re-fetching the
-- same feed window repeatedly is naturally a no-op via the upsert on
-- (source_id, source_record_id)). Offsets spread 5 minutes apart from
-- G1's :10 and BBC's :25 so six more concurrent adapter runs against
-- the same edge function don't all land in the same single minute —
-- not a correctness requirement (independent HTTP calls, no shared
-- resource contention), just spreads load a little.
select cron.schedule(
  'ingest-diario-online-4h',
  '5 */4 * * *',
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'DiarioOnlineAdapter')
  );
  $$
);

select cron.schedule(
  'ingest-cnn-brasil-4h',
  '15 */4 * * *',
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'CnnBrasilAdapter')
  );
  $$
);

select cron.schedule(
  'ingest-metropoles-4h',
  '20 */4 * * *',
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'MetropolesAdapter')
  );
  $$
);

select cron.schedule(
  'ingest-uol-4h',
  '30 */4 * * *',
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'UolAdapter')
  );
  $$
);

select cron.schedule(
  'ingest-agencia-brasil-4h',
  '35 */4 * * *',
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'AgenciaBrasilAdapter')
  );
  $$
);

select cron.schedule(
  'ingest-folha-4h',
  '40 */4 * * *',
  $$
  select net.http_post(
    url := 'https://brjzkdtkmewbodpqjhkj.supabase.co/functions/v1/ingest-security-sources',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('adapter', 'FolhaAdapter')
  );
  $$
);
