begin;

-- Make the Edge Function's access to the lobby layer explicit.
--
-- The lobby migrations end with `revoke all on function ... from public, anon,
-- authenticated`, which is the right thing to do for clients. But `service_role`
-- reaching those functions was left to whatever Supabase's default privileges
-- happen to grant, and PUBLIC is one of the ways a role can inherit EXECUTE —
-- the very grant being revoked. If the revoke takes service_role's access with
-- it, rpc("claim_match_lobby") fails, joinSharedLobby returns null, and every
-- /join falls through to the private one-player deployment. That failure is
-- silent and looks from the outside exactly like "we keep landing in different
-- matches", which is what players reported after the lobby fixes.
--
-- Granting explicitly costs nothing and removes the question. Clients still
-- cannot reach any of this: anon and authenticated keep their revokes, and both
-- tables have RLS on with no policies, which service_role bypasses by design.

grant execute on function public.claim_match_lobby(text, uuid, text, integer, integer, text)
    to service_role;
grant execute on function public.leave_match_lobby(uuid) to service_role;

grant select, insert, update, delete on public.match_lobbies to service_role;
grant select, insert, update, delete on public.match_lobby_players to service_role;

-- Re-assert the client-side revokes so the intent survives this migration.
revoke all on function public.claim_match_lobby(text, uuid, text, integer, integer, text)
    from public, anon, authenticated;
revoke all on function public.leave_match_lobby(uuid) from public, anon, authenticated;

commit;
