-- Conduit standard-account identity and daemon binding.
-- Run through the Supabase migration runner; this file contains no API keys,
-- service-role values, or SMTP credentials.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.daemon_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 120),
  public_key_fingerprint text not null check (char_length(public_key_fingerprint) between 16 and 256),
  credential_hash text not null check (char_length(credential_hash) = 64),
  bound_at timestamptz not null default now(),
  last_seen_at timestamptz,
  revoked_at timestamptz,
  unique (user_id, public_key_fingerprint)
);

-- Pairing secrets are only ever hashed. The backend service role owns this
-- table; authenticated clients bind/revoke through backend endpoints instead
-- of gaining a direct policy that could expose or modify challenges.
create table if not exists public.daemon_pairing_challenges (
  id text primary key check (char_length(id) between 16 and 128),
  user_id uuid references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 120),
  public_key_fingerprint text not null check (char_length(public_key_fingerprint) between 16 and 256),
  secret_hash text not null check (char_length(secret_hash) = 64),
  expires_at timestamptz not null,
  bound_at timestamptz,
  redeemed_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists daemon_devices_user_active_idx
  on public.daemon_devices (user_id, bound_at desc)
  where revoked_at is null;
create index if not exists daemon_pairing_challenges_user_idx
  on public.daemon_pairing_challenges (user_id, created_at desc);
create index if not exists daemon_pairing_challenges_expiry_idx
  on public.daemon_pairing_challenges (expires_at)
  where redeemed_at is null and revoked_at is null;

alter table public.profiles enable row level security;
alter table public.daemon_devices enable row level security;
alter table public.daemon_pairing_challenges enable row level security;

revoke all on public.profiles, public.daemon_devices, public.daemon_pairing_challenges from anon;
grant select, update on public.profiles to authenticated;
grant select on public.daemon_devices to authenticated;

drop policy if exists profiles_select_self on public.profiles;
create policy profiles_select_self on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

drop policy if exists daemon_devices_select_self on public.daemon_devices;
create policy daemon_devices_select_self on public.daemon_devices
  for select to authenticated
  using ((select auth.uid()) = user_id);

-- No authenticated policy exists for daemon_pairing_challenges. Only the
-- backend's service role creates, binds, redeems, or revokes a challenge.

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, coalesce(new.email, ''))
  on conflict (id) do update
  set email = excluded.email, updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
  after insert or update of email on auth.users
  for each row execute procedure public.handle_new_user_profile();
