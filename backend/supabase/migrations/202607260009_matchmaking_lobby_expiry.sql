begin;

-- Stop handing players back a finished lobby.
--
-- claim_match_lobby's first branch returned any lobby the caller was still a
-- member of, with only `status in ('filling','ready') and closed_at is null` as
-- the test. Nothing ever set closed_at once a match started, so membership was
-- permanent: after a player's first online match, every later "play online"
-- returned that same dead lobby and its stale Edgegap request_id. The client
-- then polled the status of a deployment that no longer existed and got
-- Status.TERMINATED back, which is the intermittent "server connection failed".
--
-- It also made shared matches impossible for exactly the people the lobbies
-- were built for: two friends who had each played before were both pinned to
-- their own old lobbies, so they could never be put in the same new one.
--
-- A lobby is now only reusable while it is still collecting players, and
-- lobbies whose queueing window closed are retired.

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

    -- Retire lobbies whose queueing window closed a while ago. Their match has
    -- either started or never will, so neither they nor their members should
    -- influence a new queue. The grace period keeps a lobby that is mid-deploy
    -- (deploy runs seconds after the window opens) well clear of this sweep.
    update public.match_lobbies
    set status = 'closed',
        closed_at = now()
    where closed_at is null
      and fill_deadline < now() - interval '90 seconds';

    -- Already queued in a lobby that has not been retired: a double tap, a
    -- client retry, or a player waiting out the deploy must land on the same
    -- lobby, not open a second one. The window here is deliberately the same
    -- 90 seconds the sweep above uses, so a player still being placed into a
    -- just-closed window rejoins their own match instead of splitting off.
    select l.* into v_lobby
    from public.match_lobbies l
    join public.match_lobby_players p on p.lobby_id = l.id
    where p.player_id = p_player
      and l.status <> 'closed'
      and l.closed_at is null
      and l.fill_deadline > now() - interval '90 seconds'
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

-- leave_match_lobby picked "the newest lobby this player is in that is not
-- closed", which for the same reason could be a long-finished one — cancelling
-- a queue would then decrement a dead lobby and leave the real one untouched.
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
      and l.status <> 'closed'
      and l.fill_deadline > now() - interval '90 seconds'
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

revoke all on function public.claim_match_lobby(text, uuid, text, integer, integer, text)
    from public, anon, authenticated;
revoke all on function public.leave_match_lobby(uuid) from public, anon, authenticated;

commit;
