begin;

-- Let a player's account actually be deleted.
--
-- Every table that holds a player's own records deletes with them:
-- profiles, player_preferences, player_ratings, legal_acceptances, bans,
-- rating_history and their own reports are all ON DELETE CASCADE. One is not:
--
--     match_participants.user_id references auth.users(id) on delete restrict
--
-- So the first ranked match a player finishes makes their account permanently
-- undeletable. `delete from auth.users` — which is what Supabase's own admin
-- delete-user call does — fails with a foreign key violation, and there is no
-- other way through: user_id is half of match_participants' primary key, so it
-- cannot be set null either. The game ships a consent gate and an
-- account_deletion_requests table that an authenticated player may write to;
-- the request could be filed, and then never carried out.
--
-- Verified on PostgreSQL 16: with one finished ranked match on the account,
-- deleting the user raises
--   "update or delete on table users violates foreign key constraint
--    match_participants_user_id_fkey".
--
-- The participation rows of the person being erased are their data and go with
-- them. The match itself, and every other player's row in it, are untouched:
-- matches has its own primary key, and each participant row carries its own
-- placement, so nobody else's result changes.

alter table public.match_participants
    drop constraint if exists match_participants_user_id_fkey;

alter table public.match_participants
    add constraint match_participants_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade;

-- Deleting a user also walks these foreign keys, and neither had an index to
-- walk: erasing one account meant a sequential scan of every report ever filed.
create index if not exists player_reports_reporter_idx
    on public.player_reports (reporter_user_id);

-- Same for deleting a match, which cascades into rating_history and nulls the
-- reports that point at it.
create index if not exists rating_history_match_idx
    on public.rating_history (match_id);
create index if not exists player_reports_match_idx
    on public.player_reports (match_id)
    where match_id is not null;

-- And for closing a season, which cascades into every rating row it produced.
create index if not exists rating_history_season_idx
    on public.rating_history (season_id);

commit;
