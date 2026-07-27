begin;

-- Scope lobby serialization to the complete compatibility pool.
--
-- The previous advisory lock used only region_id. That was correct for keeping
-- two simultaneous players together, but it also serialized unrelated client
-- builds in the same continent. Include build_id in the 64-bit lock key so
-- incompatible releases cannot block one another and hash collisions are
-- vanishingly unlikely.
--
-- The idempotent/retry branch must use the same compatibility key. Without the
-- region/build predicates, a player who changed region or upgraded the APK
-- could be handed an older live lobby and then fail the server identity check.

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
    v_region text := coalesce(p_region, 'auto');
    v_build text := coalesce(p_build, 'colony');
    -- Past this age a lobby's container has hit MAX_MATCH_MINUTES and stopped
    -- itself, so the row cannot describe anything that is still listening.
    v_max_life constant interval := interval '16 minutes';
    -- A match this old is not worth joining: it is minutes from its own
    -- shutdown, and the player would be dropped almost immediately.
    v_join_horizon constant interval := interval '10 minutes';
begin
    perform pg_advisory_xact_lock(
        hashtextextended('colony_lobby:' || v_region || ':' || v_build, 0)
    );

    update public.match_lobbies
    set status = 'closed',
        closed_at = now()
    where closed_at is null
      and created_at < now() - v_max_life;

    -- Double taps and retries stay idempotent only inside the same compatible
    -- region/build pool.
    select l.* into v_lobby
    from public.match_lobbies l
    join public.match_lobby_players p on p.lobby_id = l.id
    where p.player_id = p_player
      and l.region_id = v_region
      and l.build_id = v_build
      and l.status <> 'closed'
      and l.closed_at is null
      and l.created_at > now() - v_max_life
    order by l.created_at desc
    limit 1;
    if found then
        return v_lobby;
    end if;

    -- Prefer the oldest compatible lobby with space. A filling lobby wins over
    -- a match already in progress, so people who queue together start together.
    select * into v_lobby
    from public.match_lobbies
    where region_id = v_region
      and build_id = v_build
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
        v_region,
        v_build,
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

grant execute on function public.claim_match_lobby(text, uuid, text, integer, integer, text)
    to service_role;
revoke all on function public.claim_match_lobby(text, uuid, text, integer, integer, text)
    from public, anon, authenticated;

commit;
