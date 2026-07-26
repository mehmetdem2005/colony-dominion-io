begin;

-- Put everyone who is searching into the same match, not just the people who
-- pressed play within the same 20 seconds.
--
-- The open-lobby search only considered lobbies still inside their fill window
-- (`status = 'filling' and fill_deadline > now()`). Once that window closed the
-- lobby was invisible, so the next player to search opened a brand new lobby
-- and a second server — even though the first match had nine free colonies and
-- had barely started. Two friends who pressed play a minute apart could never
-- meet, which is the case players actually hit.
--
-- The dedicated server already supports this: _authenticate_peer has no
-- match-started check, and assign_peer_to_available_team hands a late joiner
-- any colony that is not eliminated and not already claimed — an AI-run one
-- until then. So a running match with a free slot is joinable, and the search
-- now says so.
--
-- Ordering keeps the old behaviour first: a lobby still collecting players is
-- always preferred over one whose match is under way, so people who queue
-- together still start together.

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
    -- Past this age a lobby's container has hit MAX_MATCH_MINUTES and stopped
    -- itself, so the row cannot describe anything that is still listening.
    v_max_life constant interval := interval '16 minutes';
    -- A match this old is not worth joining: it is minutes from its own
    -- shutdown, and the player would be dropped almost immediately.
    v_join_horizon constant interval := interval '10 minutes';
begin
    perform pg_advisory_xact_lock(hashtext('colony_lobby:' || coalesce(p_region, 'auto')));

    update public.match_lobbies
    set status = 'closed',
        closed_at = now()
    where closed_at is null
      and created_at < now() - v_max_life;

    -- Already in a live lobby: a double tap, a client retry, or a player who
    -- backed out to the menu and pressed play again rejoins their own match
    -- rather than starting a second one. The Edge Function checks that the
    -- deployment is still up before it hands this back, and closes the lobby
    -- if it is not.
    select l.* into v_lobby
    from public.match_lobbies l
    join public.match_lobby_players p on p.lobby_id = l.id
    where p.player_id = p_player
      and l.status <> 'closed'
      and l.closed_at is null
      and l.created_at > now() - v_max_life
    order by l.created_at desc
    limit 1;
    if found then
        return v_lobby;
    end if;

    select * into v_lobby
    from public.match_lobbies
    where region_id = p_region
      and build_id = coalesce(p_build, 'colony')
      and status <> 'closed'
      and closed_at is null
      and human_count < target_humans
      and (
          (status = 'filling' and fill_deadline > now())
          or (request_id is not null and created_at > now() - v_join_horizon)
      )
    order by (status = 'filling' and fill_deadline > now()) desc, created_at asc
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

-- Same horizon, so cancelling a queue always acts on the lobby the player is
-- actually in.
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
      and l.status <> 'closed'
      and l.closed_at is null
      and l.created_at > now() - interval '16 minutes'
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

-- The open-lobby search now filters on build and on request_id presence too.
create index if not exists match_lobbies_joinable_idx
    on public.match_lobbies (region_id, build_id, status, created_at);

revoke all on function public.claim_match_lobby(text, uuid, text, integer, integer, text)
    from public, anon, authenticated;
revoke all on function public.leave_match_lobby(uuid) from public, anon, authenticated;

commit;
