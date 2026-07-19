begin;

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 2 and 24),
  avatar_id text not null default 'commander_blue',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.player_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  preferred_region text not null default 'auto',
  language text not null default 'tr',
  audio_settings jsonb not null default '{}'::jsonb,
  accessibility_settings jsonb not null default '{}'::jsonb,
  analytics_consent boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.seasons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  display_name text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  is_ranked boolean not null default true,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table if not exists public.player_ratings (
  user_id uuid not null references auth.users(id) on delete cascade,
  season_id uuid not null references public.seasons(id) on delete cascade,
  rating integer not null default 1000 check (rating between 0 and 100000),
  wins integer not null default 0 check (wins >= 0),
  losses integer not null default 0 check (losses >= 0),
  matches_played integer not null default 0 check (matches_played >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, season_id)
);

create table if not exists public.legal_documents (
  document_type text not null,
  version text not null,
  locale text not null default 'tr-TR',
  title text not null,
  content_hash text not null,
  published_at timestamptz not null default now(),
  required boolean not null default true,
  active boolean not null default true,
  primary key (document_type, version, locale)
);

create table if not exists public.legal_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_type text not null,
  document_version text not null,
  locale text not null default 'tr-TR',
  accepted boolean not null,
  accepted_at timestamptz not null default now(),
  app_version text not null,
  evidence_hash text,
  unique (user_id, document_type, document_version, locale)
);

create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  rivet_server_id text,
  region text not null,
  build_version text not null,
  protocol_version integer not null check (protocol_version > 0),
  ranked boolean not null default false,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  termination_reason text,
  result_signature text,
  created_at timestamptz not null default now()
);

create table if not exists public.match_participants (
  match_id uuid not null references public.matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete restrict,
  team_id integer not null check (team_id >= 0),
  placement integer check (placement > 0),
  score integer not null default 0,
  rating_before integer,
  rating_after integer,
  disconnected boolean not null default false,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (match_id, user_id)
);

create table if not exists public.player_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_user_id uuid not null references auth.users(id) on delete cascade,
  reported_user_id uuid not null references auth.users(id) on delete cascade,
  match_id uuid references public.matches(id) on delete set null,
  category text not null,
  description text not null default '',
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'rejected')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  check (reporter_user_id <> reported_user_id)
);

create table if not exists public.bans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reason text not null,
  scope text not null default 'online' check (scope in ('online', 'chat', 'ranked')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'requested' check (status in ('requested', 'processing', 'completed', 'cancelled')),
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (user_id, status)
);

create index if not exists match_participants_user_id_idx on public.match_participants(user_id);
create index if not exists matches_started_at_idx on public.matches(started_at desc);
create index if not exists reports_reported_user_idx on public.player_reports(reported_user_id, created_at desc);
create index if not exists bans_active_user_idx on public.bans(user_id, starts_at desc);

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  proposed_name text;
begin
  proposed_name := coalesce(new.raw_user_meta_data ->> 'display_name', 'QueenAnt');
  proposed_name := left(regexp_replace(trim(proposed_name), '[^[:alnum:] _.-]', '', 'g'), 24);
  if char_length(proposed_name) < 2 then
    proposed_name := 'QueenAnt';
  end if;

  insert into public.profiles (user_id, display_name)
  values (new.id, proposed_name)
  on conflict (user_id) do nothing;

  insert into public.player_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

DROP TRIGGER IF EXISTS profiles_set_updated_at ON public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

DROP TRIGGER IF EXISTS preferences_set_updated_at ON public.player_preferences;
create trigger preferences_set_updated_at
before update on public.player_preferences
for each row execute function public.set_updated_at();


create or replace function public.stamp_legal_acceptance()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.accepted_at := now();
  return new;
end;
$$;

drop trigger if exists legal_acceptances_stamp_server_time on public.legal_acceptances;
create trigger legal_acceptances_stamp_server_time
before insert or update on public.legal_acceptances
for each row execute function public.stamp_legal_acceptance();

alter table public.profiles enable row level security;
alter table public.player_preferences enable row level security;
alter table public.seasons enable row level security;
alter table public.player_ratings enable row level security;
alter table public.legal_documents enable row level security;
alter table public.legal_acceptances enable row level security;
alter table public.matches enable row level security;
alter table public.match_participants enable row level security;
alter table public.player_reports enable row level security;
alter table public.bans enable row level security;
alter table public.account_deletion_requests enable row level security;

DROP POLICY IF EXISTS profiles_select_own ON public.profiles;
create policy profiles_select_own on public.profiles
for select to authenticated
using ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
create policy profiles_update_own on public.profiles
for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS preferences_select_own ON public.player_preferences;
create policy preferences_select_own on public.player_preferences
for select to authenticated
using ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS preferences_update_own ON public.player_preferences;
create policy preferences_update_own on public.player_preferences
for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS seasons_read_active ON public.seasons;
create policy seasons_read_active on public.seasons
for select to authenticated
using (true);

DROP POLICY IF EXISTS ratings_select_own ON public.player_ratings;
create policy ratings_select_own on public.player_ratings
for select to authenticated
using ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS legal_documents_read_active ON public.legal_documents;
create policy legal_documents_read_active on public.legal_documents
for select to anon, authenticated
using (active = true and published_at <= now());

DROP POLICY IF EXISTS legal_acceptances_select_own ON public.legal_acceptances;
create policy legal_acceptances_select_own on public.legal_acceptances
for select to authenticated
using ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS legal_acceptances_insert_own ON public.legal_acceptances;
create policy legal_acceptances_insert_own on public.legal_acceptances
for insert to authenticated
with check ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS legal_acceptances_update_own ON public.legal_acceptances;
create policy legal_acceptances_update_own on public.legal_acceptances
for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS match_participants_select_own ON public.match_participants;
create policy match_participants_select_own on public.match_participants
for select to authenticated
using ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS matches_select_participant ON public.matches;
create policy matches_select_participant on public.matches
for select to authenticated
using (
  exists (
    select 1 from public.match_participants mp
    where mp.match_id = matches.id and mp.user_id = (select auth.uid())
  )
);

DROP POLICY IF EXISTS reports_insert_own ON public.player_reports;
create policy reports_insert_own on public.player_reports
for insert to authenticated
with check ((select auth.uid()) = reporter_user_id);

DROP POLICY IF EXISTS reports_select_own ON public.player_reports;
create policy reports_select_own on public.player_reports
for select to authenticated
using ((select auth.uid()) = reporter_user_id);

DROP POLICY IF EXISTS bans_select_own ON public.bans;
create policy bans_select_own on public.bans
for select to authenticated
using ((select auth.uid()) = user_id);

DROP POLICY IF EXISTS deletion_requests_own ON public.account_deletion_requests;
create policy deletion_requests_own on public.account_deletion_requests
for all to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

revoke all on public.matches from anon, authenticated;
revoke all on public.match_participants from anon, authenticated;
grant select on public.matches to authenticated;
grant select on public.match_participants to authenticated;
grant select, update on public.profiles to authenticated;
grant select, update on public.player_preferences to authenticated;
grant select on public.seasons, public.player_ratings to authenticated;
grant select on public.legal_documents to anon, authenticated;
grant select, insert, update on public.legal_acceptances to authenticated;
grant select, insert on public.player_reports to authenticated;
grant select on public.bans to authenticated;
grant select, insert, update, delete on public.account_deletion_requests to authenticated;

commit;
