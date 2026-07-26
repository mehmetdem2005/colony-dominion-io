begin;

-- Shared matchmaking lobbies.
--
-- Before this, every /join deployed a private dedicated server for that one
-- player, so two friends pressing "play online" at the same time each landed in
-- their own bot-filled match. A lobby groups players who queue within the same
-- short window and the same region onto ONE server, which the game server
-- already supports (it validates matchmaker-signed join tickets when
-- MATCH_TICKET_SECRET is set, so many humans can share a match).
--
-- Only the Edge Function (service role) touches these tables; RLS is enabled
-- with no policies so anon/authenticated clients can never read or write them.

create table if not exists public.match_lobbies (
    id uuid primary key default gen_random_uuid(),
    region_id text not null,
    build_id text not null default 'colony',
    status text not null default 'filling'
        check (status in ('filling', 'ready', 'closed')),
    -- Exactly one joiner wins this claim and performs the Edgegap deploy; the
    -- others wait for request_id to appear instead of starting a second server.
    deploy_claim uuid,
    -- Edgegap deployment identity; null until the claim winner's deploy returns.
    request_id text,
    match_id uuid,
    server_id uuid,
    host text,
    port integer,
    human_count integer not null default 0 check (human_count >= 0),
    target_humans integer not null default 10 check (target_humans between 1 and 10),
    fill_deadline timestamptz not null,
    created_at timestamptz not null default now(),
    closed_at timestamptz
);

create index if not exists match_lobbies_open_idx
    on public.match_lobbies (region_id, status, fill_deadline);
create index if not exists match_lobbies_request_idx
    on public.match_lobbies (request_id);

create table if not exists public.match_lobby_players (
    lobby_id uuid not null references public.match_lobbies (id) on delete cascade,
    player_id uuid not null,
    display_name text not null default 'Player',
    joined_at timestamptz not null default now(),
    primary key (lobby_id, player_id)
);

create index if not exists match_lobby_players_player_idx
    on public.match_lobby_players (player_id);

alter table public.match_lobbies enable row level security;
alter table public.match_lobby_players enable row level security;

-- Join an open lobby for this region, or open a new one. A per-region advisory
-- lock plus SKIP LOCKED keeps two simultaneous joiners from each creating their
-- own lobby, which is exactly the race that made friends land in separate
-- matches. Returns the lobby the caller belongs to; when request_id comes back
-- null the caller is the creator and must deploy the server.
create or replace function public.claim_match_lobby(
    p_region text,
    p_player uuid,
    p_name text,
    p_target integer,
    p_window_seconds integer,
    p_build text
) returns public.match_lobbies
language plpgsql
security definer
set search_path = public
as $$
declare
    v_lobby public.match_lobbies;
begin
    perform pg_advisory_xact_lock(hashtext('colony_lobby:' || coalesce(p_region, 'auto')));

    -- Already queued (double tap, reconnect, retry): keep the same lobby.
    select l.* into v_lobby
    from public.match_lobbies l
    join public.match_lobby_players p on p.lobby_id = l.id
    where p.player_id = p_player
      and l.status in ('filling', 'ready')
      and l.closed_at is null
    order by l.created_at desc
    limit 1;
    if found then
        return v_lobby;
    end if;

    select * into v_lobby
    from public.match_lobbies
    where region_id = p_region
      and status = 'filling'
      and closed_at is null
      and fill_deadline > now()
      and human_count < target_humans
    order by created_at asc
    for update skip locked
    limit 1;

    if found then
        insert into public.match_lobby_players (lobby_id, player_id, display_name)
        values (v_lobby.id, p_player, p_name)
        on conflict (lobby_id, player_id) do nothing;

        update public.match_lobbies
        set human_count = (
            select count(*) from public.match_lobby_players where lobby_id = v_lobby.id
        )
        where id = v_lobby.id
        returning * into v_lobby;
        return v_lobby;
    end if;

    insert into public.match_lobbies (
        region_id, build_id, target_humans, human_count, fill_deadline
    )
    values (
        p_region,
        coalesce(p_build, 'colony'),
        greatest(least(coalesce(p_target, 10), 10), 1),
        1,
        now() + make_interval(secs => greatest(coalesce(p_window_seconds, 20), 5))
    )
    returning * into v_lobby;

    insert into public.match_lobby_players (lobby_id, player_id, display_name)
    values (v_lobby.id, p_player, p_name);

    return v_lobby;
end;
$$;

-- Drop a player from their lobby. Returns the lobby with its remaining count so
-- the caller can stop the deployment only when the last player backs out — a
-- cancel must never kill a match the others are still waiting for.
create or replace function public.leave_match_lobby(p_player uuid)
returns public.match_lobbies
language plpgsql
security definer
set search_path = public
as $$
declare
    v_lobby public.match_lobbies;
begin
    select l.* into v_lobby
    from public.match_lobbies l
    join public.match_lobby_players p on p.lobby_id = l.id
    where p.player_id = p_player
      and l.closed_at is null
    order by l.created_at desc
    limit 1;
    if not found then
        return null;
    end if;

    delete from public.match_lobby_players
    where lobby_id = v_lobby.id and player_id = p_player;

    update public.match_lobbies
    set human_count = (
            select count(*) from public.match_lobby_players where lobby_id = v_lobby.id
        ),
        status = case
            when (select count(*) from public.match_lobby_players where lobby_id = v_lobby.id) = 0
                then 'closed'
            else status
        end,
        closed_at = case
            when (select count(*) from public.match_lobby_players where lobby_id = v_lobby.id) = 0
                then now()
            else closed_at
        end
    where id = v_lobby.id
    returning * into v_lobby;

    return v_lobby;
end;
$$;

revoke all on function public.claim_match_lobby(text, uuid, text, integer, integer, text) from public, anon, authenticated;
revoke all on function public.leave_match_lobby(uuid) from public, anon, authenticated;

commit;
