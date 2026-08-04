#!/usr/bin/env python3
"""PostgreSQL integration test for erasing a player account.

The game ships a consent gate and an account_deletion_requests table that an
authenticated player may write to, so deleting an account is a promise the
schema has to be able to keep. It could not: match_participants.user_id
referenced auth.users ON DELETE RESTRICT, so the first ranked match a player
finished made their account permanently undeletable — including through
Supabase's own admin delete-user call, which is a plain `delete from
auth.users`.

This applies the real migrations to a disposable database and checks the whole
promise end to end: the account goes, the player's own records go with it, and
the match itself and everyone else in it are left alone.
"""

from __future__ import annotations

import argparse
import os
import uuid
from pathlib import Path

import psycopg


ROOT = Path(__file__).resolve().parents[1]
MIGRATION_DIR = ROOT / "backend" / "supabase" / "migrations"

# Enough of Supabase's auth schema for the production migrations to apply: the
# columns the new-user trigger reads, and the two helpers the RLS policies call.
AUTH_SHIM = """
create extension if not exists pgcrypto;
do $$ begin create role anon noinherit; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated noinherit; exception when duplicate_object then null; end $$;
do $$ begin create role service_role noinherit bypassrls; exception when duplicate_object then null; end $$;
create schema if not exists auth;
create table if not exists auth.users (
    id uuid primary key default gen_random_uuid(),
    email text,
    raw_user_meta_data jsonb not null default '{}'::jsonb
);
create or replace function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;
create or replace function auth.role() returns text language sql stable as $$ select 'service_role'::text $$;
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--database-url",
        default=os.environ.get(
            "MATCHMAKING_TEST_DATABASE_URL",
            "postgresql://postgres:postgres@127.0.0.1:5432/postgres",
        ),
    )
    return parser.parse_args()


def install_schema(connection: psycopg.Connection) -> None:
    connection.execute("drop schema if exists public cascade")
    connection.execute("create schema public")
    connection.execute("drop schema if exists auth cascade")
    connection.execute(AUTH_SHIM)
    for migration in sorted(MIGRATION_DIR.glob("*.sql")):
        connection.execute(migration.read_text(encoding="utf-8"))


def seed_finished_ranked_match(
    connection: psycopg.Connection,
) -> tuple[uuid.UUID, uuid.UUID, uuid.UUID]:
    leaver = uuid.uuid4()
    stayer = uuid.uuid4()
    match_id = uuid.uuid4()
    season_id = uuid.uuid4()
    connection.execute(
        "insert into auth.users (id, email) values (%s, %s), (%s, %s)",
        (leaver, "leaver@example.test", stayer, "stayer@example.test"),
    )
    connection.execute(
        """
        insert into public.seasons (id, code, display_name, starts_at, ends_at)
        values (%s, 'deletion-test', 'Deletion Test',
                now() - interval '1 day', now() + interval '30 days')
        """,
        (season_id,),
    )
    connection.execute(
        """
        insert into public.matches (
            id, season_id, region, build_version, protocol_version,
            started_at, ended_at, ranked
        )
        values (%s, %s, 'frankfurt', 'test-build', 4, now(), now(), true)
        """,
        (match_id, season_id),
    )
    for index, user_id in enumerate((leaver, stayer)):
        connection.execute(
            """
            insert into public.match_participants (
                match_id, user_id, season_id, team_id, placement
            )
            values (%s, %s, %s, %s, %s)
            """,
            (match_id, user_id, season_id, index, index + 1),
        )
        connection.execute(
            """
            insert into public.rating_history (
                user_id, match_id, season_id,
                rating_before, rating_after, rating_delta, placement
            )
            values (%s, %s, %s, 1000, 1020, 20, %s)
            """,
            (user_id, match_id, season_id, index + 1),
        )
    return leaver, stayer, match_id


def assert_account_can_be_erased(database_url: str) -> None:
    with psycopg.connect(database_url, autocommit=True) as connection:
        install_schema(connection)
        leaver, stayer, match_id = seed_finished_ranked_match(connection)

        # The plain delete Supabase's admin API performs.
        connection.execute("delete from auth.users where id = %s", (leaver,))

        remaining_rows = connection.execute(
            """
            select
                (select count(*) from public.match_participants where user_id = %s),
                (select count(*) from public.rating_history where user_id = %s),
                (select count(*) from public.profiles where user_id = %s)
            """,
            (leaver, leaver, leaver),
        ).fetchone()
        assert remaining_rows == (0, 0, 0), f"erased account left rows behind: {remaining_rows}"

        survivors = connection.execute(
            """
            select
                (select count(*) from public.matches where id = %s),
                (select count(*) from public.match_participants where user_id = %s),
                (select count(*) from public.rating_history where user_id = %s)
            """,
            (match_id, stayer, stayer),
        ).fetchone()
        assert survivors == (1, 1, 1), f"erasing one account disturbed the match: {survivors}"


def assert_user_deletion_walks_indexes(database_url: str) -> None:
    """Erasing an account must not scan every report ever filed.

    Postgres walks each referencing foreign key when a row is deleted, and an
    unindexed one is a sequential scan of the child table per deleted user.
    """
    with psycopg.connect(database_url, autocommit=True) as connection:
        unindexed = connection.execute(
            """
            select c.conrelid::regclass::text, a.attname
            from pg_constraint c
            join lateral unnest(c.conkey) k(attnum) on true
            join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
            where c.contype = 'f'
              and c.connamespace = 'public'::regnamespace
              and not exists (
                  select 1 from pg_index i
                  where i.indrelid = c.conrelid and i.indkey[0] = k.attnum
              )
            order by 1, 2
            """
        ).fetchall()
        assert not unindexed, f"foreign keys with no index behind them: {unindexed}"


def main() -> int:
    database_url = parse_args().database_url
    assert_account_can_be_erased(database_url)
    assert_user_deletion_walks_indexes(database_url)
    print("PASS account deletion PostgreSQL contract")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
