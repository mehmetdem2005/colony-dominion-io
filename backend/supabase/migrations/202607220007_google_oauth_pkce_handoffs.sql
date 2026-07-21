begin;

alter table public.oauth_handoffs
  add column if not exists flow_type text not null default 'pkce',
  add column if not exists callback_nonce_hash text,
  add column if not exists auth_code text;

-- Handoffs are short-lived and cannot be safely upgraded in place from
-- implicit tokens to PKCE authorization codes. Remove any in-flight legacy row.
delete from public.oauth_handoffs;

alter table public.oauth_handoffs
  drop constraint if exists oauth_handoffs_flow_type_check,
  drop constraint if exists oauth_handoffs_callback_nonce_hash_check,
  drop constraint if exists oauth_handoffs_auth_code_check;

alter table public.oauth_handoffs
  add constraint oauth_handoffs_flow_type_check
    check (flow_type = 'pkce'),
  add constraint oauth_handoffs_callback_nonce_hash_check
    check (
      callback_nonce_hash is null
      or callback_nonce_hash ~ '^[0-9a-f]{64}$'
    ),
  add constraint oauth_handoffs_auth_code_check
    check (
      auth_code is null
      or char_length(auth_code) between 8 and 2048
    );

create index if not exists oauth_handoffs_completed_at_idx
on public.oauth_handoffs(completed_at)
where completed_at is not null;

comment on column public.oauth_handoffs.auth_code is
  'Single-use Supabase PKCE authorization code; never an access or refresh token.';
comment on column public.oauth_handoffs.callback_nonce_hash is
  'SHA-256 hash binding the browser callback path to one handoff.';
comment on column public.oauth_handoffs.flow_type is
  'OAuth handoff protocol. Only PKCE is accepted.';

commit;
