begin;

drop function if exists public.record_authoritative_match_result(
  uuid, text, text, text, integer, timestamptz, timestamptz, text, jsonb
);

create or replace function public.record_authoritative_match_result(
  p_match_id uuid,
  p_rivet_server_id text,
  p_region text,
  p_build_version text,
  p_protocol_version integer,
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_termination_reason text,
  p_participants jsonb,
  p_ranked boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_participant jsonb;
  v_opponent jsonb;
  v_participant_count integer;
  v_distinct_players integer;
  v_distinct_placements integer;
  v_season_id uuid;
  v_existing_processed_at timestamptz;
  v_user_ids uuid[];
  v_user_id uuid;
  v_opponent_id uuid;
  v_placement integer;
  v_score integer;
  v_disconnected boolean;
  v_rating integer;
  v_opponent_rating integer;
  v_matches_played integer;
  v_expected numeric;
  v_expected_total numeric;
  v_expected_count integer;
  v_actual numeric;
  v_k integer;
  v_delta integer;
  v_new_rating integer;
  v_result_rows jsonb := '[]'::jsonb;
begin
  if p_ended_at < p_started_at then
    raise exception 'ended_at must not precede started_at';
  end if;
  if p_protocol_version <= 0 then
    raise exception 'protocol_version must be positive';
  end if;
  if jsonb_typeof(p_participants) <> 'array' then
    raise exception 'participants must be a JSON array';
  end if;

  select
    count(*),
    count(distinct (value ->> 'player_id')),
    count(distinct ((value ->> 'placement')::integer)),
    array_agg((value ->> 'player_id')::uuid order by (value ->> 'player_id'))
  into
    v_participant_count,
    v_distinct_players,
    v_distinct_placements,
    v_user_ids
  from jsonb_array_elements(p_participants);

  if v_participant_count < 1 or v_participant_count > 32 then
    raise exception 'participant count must be between 1 and 32';
  end if;
  if v_distinct_players <> v_participant_count then
    raise exception 'participant player ids must be unique';
  end if;
  if v_distinct_placements <> v_participant_count then
    raise exception 'participant placements must be unique';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_match_id::text, 0));

  select ratings_processed_at
  into v_existing_processed_at
  from public.matches
  where id = p_match_id;

  if v_existing_processed_at is not null then
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'match_id', p_match_id,
      'ratings_processed_at', v_existing_processed_at
    );
  end if;

  insert into public.matches (
    id,
    rivet_server_id,
    region,
    build_version,
    protocol_version,
    ranked,
    started_at,
    ended_at,
    termination_reason
  )
  values (
    p_match_id,
    left(p_rivet_server_id, 128),
    left(p_region, 32),
    left(p_build_version, 96),
    p_protocol_version,
    false,
    p_started_at,
    p_ended_at,
    left(p_termination_reason, 64)
  )
  on conflict (id) do update set
    rivet_server_id = excluded.rivet_server_id,
    region = excluded.region,
    build_version = excluded.build_version,
    protocol_version = excluded.protocol_version,
    started_at = excluded.started_at,
    ended_at = excluded.ended_at,
    termination_reason = excluded.termination_reason;

  for v_participant in select value from jsonb_array_elements(p_participants)
  loop
    v_user_id := (v_participant ->> 'player_id')::uuid;
    v_placement := greatest((v_participant ->> 'placement')::integer, 1);
    if v_placement > v_participant_count then
      raise exception 'placement exceeds participant count';
    end if;
    v_score := greatest(coalesce((v_participant ->> 'score')::integer, 0), 0);
    v_disconnected := coalesce((v_participant ->> 'disconnected')::boolean, false);

    insert into public.match_participants (
      match_id,
      user_id,
      team_id,
      placement,
      score,
      disconnected,
      won,
      left_at
    )
    values (
      p_match_id,
      v_user_id,
      greatest((v_participant ->> 'team_id')::integer, 0),
      v_placement,
      v_score,
      v_disconnected,
      v_placement = 1,
      case when v_disconnected then p_ended_at else null end
    )
    on conflict (match_id, user_id) do update set
      team_id = excluded.team_id,
      placement = excluded.placement,
      score = excluded.score,
      disconnected = excluded.disconnected,
      won = excluded.won,
      left_at = excluded.left_at;
  end loop;

  if p_ranked and v_participant_count >= 2 then
    select id
    into v_season_id
    from public.seasons
    where is_ranked
      and starts_at <= p_ended_at
      and ends_at > p_ended_at
    order by starts_at desc
    limit 1;
  end if;

  if v_season_id is null then
    update public.matches
    set ranked = false,
        season_id = null,
        ratings_processed_at = now()
    where id = p_match_id;
    return jsonb_build_object(
      'ok', true,
      'idempotent', false,
      'ranked', false,
      'match_id', p_match_id,
      'ratings', '[]'::jsonb
    );
  end if;

  for v_user_id in select unnest(v_user_ids)
  loop
    insert into public.player_ratings (user_id, season_id)
    values (v_user_id, v_season_id)
    on conflict (user_id, season_id) do nothing;
  end loop;

  perform 1
  from public.player_ratings
  where season_id = v_season_id
    and user_id = any(v_user_ids)
  order by user_id
  for update;

  for v_participant in select value from jsonb_array_elements(p_participants)
  loop
    v_user_id := (v_participant ->> 'player_id')::uuid;
    v_placement := greatest((v_participant ->> 'placement')::integer, 1);
    v_disconnected := coalesce((v_participant ->> 'disconnected')::boolean, false);

    select rating, matches_played
    into v_rating, v_matches_played
    from public.player_ratings
    where user_id = v_user_id and season_id = v_season_id;

    v_expected_total := 0.0;
    v_expected_count := 0;
    for v_opponent in select value from jsonb_array_elements(p_participants)
    loop
      v_opponent_id := (v_opponent ->> 'player_id')::uuid;
      if v_opponent_id = v_user_id then
        continue;
      end if;
      select rating
      into v_opponent_rating
      from public.player_ratings
      where user_id = v_opponent_id and season_id = v_season_id;
      v_expected_total := v_expected_total + (
        1.0 / (1.0 + power(10.0, (v_opponent_rating - v_rating) / 400.0))
      );
      v_expected_count := v_expected_count + 1;
    end loop;

    v_expected := case
      when v_expected_count > 0 then v_expected_total / v_expected_count
      else 0.5
    end;
    v_actual := (v_participant_count - v_placement)::numeric
      / greatest(v_participant_count - 1, 1)::numeric;
    if v_disconnected then
      v_actual := greatest(v_actual - 0.05, 0.0);
    end if;
    v_k := case
      when v_matches_played < 10 then 48
      when v_matches_played < 30 then 32
      else 24
    end;
    v_delta := greatest(-64, least(64, round(v_k * (v_actual - v_expected))::integer));
    v_new_rating := greatest(0, v_rating + v_delta);

    update public.player_ratings
    set rating = v_new_rating,
        peak_rating = greatest(peak_rating, v_new_rating),
        wins = wins + case when v_placement = 1 then 1 else 0 end,
        losses = losses + case when v_placement > 1 then 1 else 0 end,
        matches_played = matches_played + 1,
        provisional_matches = greatest(provisional_matches - 1, 0),
        updated_at = now()
    where user_id = v_user_id and season_id = v_season_id;

    update public.match_participants
    set season_id = v_season_id,
        rating_before = v_rating,
        rating_after = v_new_rating,
        rating_delta = v_delta,
        won = v_placement = 1
    where match_id = p_match_id and user_id = v_user_id;

    insert into public.rating_history (
      user_id,
      season_id,
      match_id,
      rating_before,
      rating_after,
      rating_delta,
      placement
    ) values (
      v_user_id,
      v_season_id,
      p_match_id,
      v_rating,
      v_new_rating,
      v_delta,
      v_placement
    ) on conflict (user_id, match_id) do nothing;

    v_result_rows := v_result_rows || jsonb_build_array(
      jsonb_build_object(
        'player_id', v_user_id,
        'rating_before', v_rating,
        'rating_after', v_new_rating,
        'rating_delta', v_delta,
        'placement', v_placement
      )
    );
  end loop;

  update public.matches
  set ranked = true,
      season_id = v_season_id,
      ratings_processed_at = now()
  where id = p_match_id;

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'ranked', true,
    'match_id', p_match_id,
    'season_id', v_season_id,
    'ratings', v_result_rows
  );
end;
$$;

revoke all on function public.record_authoritative_match_result(
  uuid, text, text, text, integer, timestamptz, timestamptz, text, jsonb, boolean
) from public, anon, authenticated;
grant execute on function public.record_authoritative_match_result(
  uuid, text, text, text, integer, timestamptz, timestamptz, text, jsonb, boolean
) to service_role;

create or replace function public.get_my_ranked_summary()
returns table (
  season_code text,
  season_name text,
  rating integer,
  wins integer,
  losses integer,
  matches_played integer,
  rank_position bigint
)
language sql
security definer
set search_path = ''
as $$
  with active_season as (
    select id, code, display_name, starts_at
    from public.seasons
    where is_ranked
      and starts_at <= now()
      and ends_at > now()
    order by starts_at desc
    limit 1
  ), ranked as (
    select
      pr.user_id,
      pr.season_id,
      pr.rating,
      pr.wins,
      pr.losses,
      pr.matches_played,
      rank() over (order by pr.rating desc, pr.matches_played desc, pr.user_id) as rank_position
    from public.player_ratings pr
    join active_season active on active.id = pr.season_id
  )
  select
    active.code,
    active.display_name,
    ranked.rating,
    ranked.wins,
    ranked.losses,
    ranked.matches_played,
    ranked.rank_position
  from ranked
  join active_season active on active.id = ranked.season_id
  where ranked.user_id = (select auth.uid());
$$;

revoke all on function public.get_my_ranked_summary() from public, anon;
grant execute on function public.get_my_ranked_summary() to authenticated;

commit;
