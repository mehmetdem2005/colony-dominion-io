begin;

-- Keep the cost of joining a match constant as the game grows.
--
-- This carries forward everything 202607270012 established — the advisory lock
-- keyed on region *and* build, and the region/build predicates on the
-- idempotent branch — and fixes what it left unbounded.
--
-- claim_match_lobby runs a retirement sweep on every single call:
--
--     update match_lobbies set status = 'closed' ...
--     where closed_at is null and created_at < now() - interval '16 minutes'
--
-- with no index behind it and no limit on how many rows it can touch, while
-- holding the advisory lock that serialises every join for that pool.
-- match_lobbies is also append-only: nothing ever deleted a row. So the work
-- done per join grows with the number of matches ever played, and it grows
-- inside the one lock every player has to pass through. That is fine at ten
-- matches and ruinous at ten million.
--
-- Three changes, none of which alter who gets matched with whom:
--
--   * a partial index over exactly the rows the sweep looks for, so finding
--     them costs a lookup instead of a scan;
--   * a LIMIT on the sweep, so one join can never be made slow by a backlog —
--     the next join picks up where it left off;
--   * retention, so the table stops growing forever. Closed lobbies older than
--     a day are deleted in the same bounded way, and match_lobby_players goes
--     with them on cascade.

create index if not exists match_lobbies_open_sweep_idx
    on public.match_lobbies (created_at)
    where closed_at is null;

create index if not exists match_lobbies_retention_idx
    on public.match_lobbies (closed_at)
    where closed_at is not null;

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
begin
    perform pg_advisory_xact_lock(
        hashtextextended('colony_lobby:' || v_region || ':' || v_build, 0)
    );

    update public.match_lobbies
    set status = 'closed',
        closed_at = now()
    where id in (
        select id
        from public.match_lobbies
        where closed_at is null
          and created_at < now() - v_max_life
        order by created_at
        limit v_sweep_limit
    );

    delete from public.match_lobbies
    where id in (
        select id
        from public.match_lobbies
        where closed_at is not null
          and closed_at < now() - interval '1 day'
        order by closed_at
        limit v_sweep_limit
    );

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
