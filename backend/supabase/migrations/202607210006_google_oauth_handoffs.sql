begin;

create table if not exists public.oauth_handoffs (
  request_id uuid primary key,
  secret_hash text not null check (secret_hash ~ '^[0-9a-f]{64}$'),
  refresh_token text,
  error_message text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '5 minutes'),
  completed_at timestamptz,
  consumed_at timestamptz,
  check (expires_at > created_at),
  check (refresh_token is null or char_length(refresh_token) between 16 and 4096),
  check (error_message is null or char_length(error_message) <= 500)
);

create index if not exists oauth_handoffs_expires_at_idx
on public.oauth_handoffs(expires_at);

alter table public.oauth_handoffs enable row level security;
revoke all on table public.oauth_handoffs from anon, authenticated;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  proposed_name text;
begin
  proposed_name := coalesce(
    nullif(new.raw_user_meta_data ->> 'display_name', ''),
    nullif(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'name', ''),
    split_part(coalesce(new.email, ''), '@', 1),
    'QueenAnt'
  );
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

commit;
