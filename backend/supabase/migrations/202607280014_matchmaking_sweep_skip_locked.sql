begin;

-- Stop matchmaking deadlocking itself once the game is busy.
--
-- claim_match_lobby holds an advisory lock keyed on region and build, so two
-- joiners in different regions are supposed to run side by side. They do not:
-- before reaching that pool's own rows, every call runs the retirement sweep
-- and the retention delete over the WHOLE table.
--
--     update public.match_lobbies set status = 'closed', closed_at = now()
--     where id in (
--         select id from public.match_lobbies
--         where closed_at is null and created_at < now() - interval '16 minutes'
--         order by created_at limit 50
--     )
--
-- Every concurrent joiner, whatever region they are in, aims at the same fifty
-- oldest rows. `order by created_at` does not save them: created_at is not
-- unique, and after a concurrent update Postgres re-checks the tuple and can
-- take the remaining row locks in a different order. So they do not merely
-- queue behind each other — they deadlock, and a deadlock is a matchmaking
-- request that fails outright. The player is told the match could not be
-- started, for no reason they could ever act on.
--
-- Reproduced on PostgreSQL 16 with eight joiners in eight different regions and
-- a backlog of open lobbies: three deadlocks in 1600 calls, every one of them
-- inside this sweep.
--
-- FOR UPDATE SKIP LOCKED makes each caller take the oldest rows nobody else
-- holds. Concurrent sweepers get disjoint sets, so there is nothing to wait for
-- and nothing to deadlock over, and the backlog still drains at fifty rows per
-- join. Nothing about who is matched with whom changes.

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
    -- How much cleanup a single join is allowed to pay for. A backlog is spread
    -- over the joins that follow instead of landing on one unlucky player.
    v_sweep_limit constant integer := 50;
    v_sweep_ids uuid[];
begin
    perform pg_advisory_xact_lock(
        hashtextextended('colony_lobby:' || v_region || ':' || v_build, 0)
    );

    select array_agg(id) into v_sweep_ids
    from (
        select id
        from public.match_lobbies
        where closed_at is null
          and created_at < now() - v_max_life
        order by created_at
        limit v_sweep_limit
        for update skip locked
    ) stale;
    if v_sweep_ids is not null then
        update public.match_lobbies
        set status = 'closed',
            closed_at = now()
        where id = any (v_sweep_ids);
    end if;

    select array_agg(id) into v_sweep_ids
    from (
        select id
        from public.match_lobbies
        where closed_at is not null
          and closed_at < now() - interval '1 day'
        order by closed_at
        limit v_sweep_limit
        for update skip locked
    ) expired;
    if v_sweep_ids is not null then
        delete from public.match_lobbies where id = any (v_sweep_ids);
    end if;

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
