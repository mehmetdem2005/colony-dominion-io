begin;

alter table public.matches
  add column if not exists season_id uuid references public.seasons(id) on delete set null,
  add column if not exists ratings_processed_at timestamptz;

alter table public.match_participants
  add column if not exists season_id uuid references public.seasons(id) on delete set null,
  add column if not exists rating_delta integer,
  add column if not exists won boolean not null default false;

alter table public.player_ratings
  add column if not exists peak_rating integer not null default 1000,
  add column if not exists provisional_matches integer not null default 10;

create table if not exists public.rating_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  season_id uuid not null references public.seasons(id) on delete cascade,
  match_id uuid not null references public.matches(id) on delete cascade,
  rating_before integer not null,
  rating_after integer not null,
  rating_delta integer not null,
  placement integer not null,
  created_at timestamptz not null default now(),
  unique (user_id, match_id)
);

alter table public.rating_history enable row level security;
drop policy if exists rating_history_select_own on public.rating_history;
create policy rating_history_select_own on public.rating_history
for select to authenticated using ((select auth.uid()) = user_id);
grant select on public.rating_history to authenticated;

create index if not exists matches_season_started_idx
  on public.matches(season_id, started_at desc);
create index if not exists player_ratings_season_rating_idx
  on public.player_ratings(season_id, rating desc, matches_played desc);
create index if not exists match_participants_season_idx
  on public.match_participants(season_id, placement, user_id);
create index if not exists rating_history_user_created_idx
  on public.rating_history(user_id, created_at desc);

insert into public.seasons (code, display_name, starts_at, ends_at, is_ranked)
values (
  'S2026-PRESEASON',
  '2026 Ön Sezon',
  timestamptz '2026-07-01 00:00:00+00',
  timestamptz '2026-10-01 00:00:00+00',
  true
)
on conflict (code) do update set
  display_name = excluded.display_name,
  starts_at = excluded.starts_at,
  ends_at = excluded.ends_at,
  is_ranked = excluded.is_ranked;

create or replace function public.current_ranked_season()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id
  from public.seasons
  where is_ranked and starts_at <= now() and ends_at > now()
  order by starts_at desc
  limit 1
$$;

revoke all on function public.current_ranked_season() from public, anon;
grant execute on function public.current_ranked_season() to authenticated, service_role;

create or replace function public.get_season_leaderboard(p_limit integer default 50)
returns table (
  user_id uuid,
  display_name text,
  rating integer,
  peak_rating integer,
  wins integer,
  losses integer,
  matches_played integer,
  rank bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    ratings.user_id,
    profiles.display_name,
    ratings.rating,
    ratings.peak_rating,
    ratings.wins,
    ratings.losses,
    ratings.matches_played,
    dense_rank() over (
      order by ratings.rating desc, ratings.wins desc, ratings.updated_at asc
    ) as rank
  from public.player_ratings ratings
  join public.profiles profiles on profiles.user_id = ratings.user_id
  where ratings.season_id = public.current_ranked_season()
  order by ratings.rating desc, ratings.wins desc, ratings.updated_at asc
  limit least(greatest(p_limit, 1), 100)
$$;

revoke all on function public.get_season_leaderboard(integer) from public, anon;
grant execute on function public.get_season_leaderboard(integer) to authenticated;

commit;
