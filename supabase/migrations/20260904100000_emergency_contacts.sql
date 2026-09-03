-- One trusted contact per logged-in user, who can be notified with a
-- WhatsApp message + live location link from the SOS sheet when they feel
-- in danger. v1 scope deliberately keeps this to a single contact (not a
-- list) and a user-confirmed WhatsApp deep link (not an automatic SMS
-- provider) — see this session's design discussion: automatic SMS needs a
-- paid provider (Twilio) and a server-side Edge Function per country,
-- while wa.me is free, requires no new infra, and the confirm-to-send tap
-- doubles as protection against an accidental trigger.
create table public.emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  phone text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Single contact per user for v1 — enforced here rather than in the app
-- so it can't be bypassed by a second insert.
create unique index emergency_contacts_user_id_idx
  on public.emergency_contacts (user_id);

alter table public.emergency_contacts enable row level security;

create policy "Users see own emergency contact"
  on public.emergency_contacts for select
  using (auth.uid() = user_id);

create policy "Users insert own emergency contact"
  on public.emergency_contacts for insert
  with check (auth.uid() = user_id);

create policy "Users update own emergency contact"
  on public.emergency_contacts for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users delete own emergency contact"
  on public.emergency_contacts for delete
  using (auth.uid() = user_id);
