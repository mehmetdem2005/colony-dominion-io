begin;

create or replace function public.record_authoritative_match_result(
  p_match_id uuid,
  p_rivet_server_id text,
  p_region text,
  p_build_version text,
  p_protocol_version integer,
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_termination_reason text,
  p_participants jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  participant jsonb;
begin
  if p_ended_at < p_started_at then
    raise exception 'ended_at must not precede started_at';
  end if;
  if jsonb_typeof(p_participants) <> 'array' then
    raise exception 'participants must be a JSON array';
  end if;

  insert into public.matches (
    id,
    rivet_server_id,
    region,
    build_version,
    protocol_version,
    started_at,
    ended_at,
    termination_reason
  )
  values (
    p_match_id,
    p_rivet_server_id,
    p_region,
    p_build_version,
    p_protocol_version,
    p_started_at,
    p_ended_at,
    p_termination_reason
  )
  on conflict (id) do update set
    rivet_server_id = excluded.rivet_server_id,
    region = excluded.region,
    build_version = excluded.build_version,
    protocol_version = excluded.protocol_version,
    started_at = excluded.started_at,
    ended_at = excluded.ended_at,
    termination_reason = excluded.termination_reason;

  for participant in select value from jsonb_array_elements(p_participants)
  loop
    insert into public.match_participants (
      match_id,
      user_id,
      team_id,
      placement,
      score,
      disconnected,
      left_at
    )
    values (
      p_match_id,
      (participant ->> 'player_id')::uuid,
      greatest((participant ->> 'team_id')::integer, 0),
      greatest((participant ->> 'placement')::integer, 1),
      greatest((participant ->> 'score')::integer, 0),
      coalesce((participant ->> 'disconnected')::boolean, false),
      case
        when coalesce((participant ->> 'disconnected')::boolean, false)
          then p_ended_at
        else null
      end
    )
    on conflict (match_id, user_id) do update set
      team_id = excluded.team_id,
      placement = excluded.placement,
      score = excluded.score,
      disconnected = excluded.disconnected,
      left_at = excluded.left_at;
  end loop;
end;
$$;

revoke all on function public.record_authoritative_match_result(
  uuid, text, text, text, integer, timestamptz, timestamptz, text, jsonb
) from public, anon, authenticated;
grant execute on function public.record_authoritative_match_result(
  uuid, text, text, text, integer, timestamptz, timestamptz, text, jsonb
) to service_role;

commit;
