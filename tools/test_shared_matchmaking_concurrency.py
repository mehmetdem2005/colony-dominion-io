#!/usr/bin/env python3
"""PostgreSQL integration tests for shared-lobby matchmaking.

This runs the real production lobby migrations against a disposable PostgreSQL
database and issues claims over separate concurrent connections. It protects the
core invariant: players entering the same compatible queue are grouped into one
lobby up to its ten-player capacity, never one private lobby per request.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import os
import threading
import uuid
from collections import Counter
from pathlib import Path

import psycopg


ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = (
    "202607250008_matchmaking_lobbies.sql",
    "202607260009_matchmaking_lobby_expiry.sql",
    "202607260010_matchmaking_join_in_progress.sql",
    "202607260011_matchmaking_lobby_grants.sql",
    "202607270012_matchmaking_compatibility_lock.sql",
)


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


def install_schema(database_url: str) -> None:
    bootstrap = """
    create extension if not exists pgcrypto;
    do $$ begin create role anon noinherit; exception when duplicate_object then null; end $$;
    do $$ begin create role authenticated noinherit; exception when duplicate_object then null; end $$;
    do $$ begin create role service_role noinherit bypassrls; exception when duplicate_object then null; end $$;
    drop table if exists public.match_lobby_players cascade;
    drop table if exists public.match_lobbies cascade;
    """
    with psycopg.connect(database_url, autocommit=True) as connection:
        connection.execute(bootstrap)
        for filename in MIGRATIONS:
            sql = (ROOT / "backend" / "supabase" / "migrations" / filename).read_text(
                encoding="utf-8"
            )
            connection.execute(sql)


def claim(
    database_url: str,
    *,
    barrier: threading.Barrier | None,
    region: str,
    player_id: uuid.UUID,
    build_id: str,
    target: int = 10,
) -> tuple[str, int]:
    with psycopg.connect(database_url, autocommit=True) as connection:
        if barrier is not None:
            barrier.wait(timeout=15)
        row = connection.execute(
            """
            select id::text, human_count
            from public.claim_match_lobby(%s, %s, %s, %s, %s, %s)
            """,
            (region, player_id, f"Player-{str(player_id)[:8]}", target, 20, build_id),
        ).fetchone()
    if row is None:
        raise AssertionError("claim_match_lobby returned no lobby")
    return str(row[0]), int(row[1])


def claim_cohort(
    database_url: str,
    *,
    players: int,
    region: str,
    build_id: str,
    target: int = 10,
) -> list[tuple[str, int]]:
    barrier = threading.Barrier(players)
    player_ids = [uuid.uuid4() for _ in range(players)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=players) as executor:
        futures = [
            executor.submit(
                claim,
                database_url,
                barrier=barrier,
                region=region,
                player_id=player_id,
                build_id=build_id,
                target=target,
            )
            for player_id in player_ids
        ]
        return [future.result(timeout=30) for future in futures]


def lobby_counts(database_url: str, *, region: str, build_id: str) -> list[int]:
    with psycopg.connect(database_url, autocommit=True) as connection:
        rows = connection.execute(
            """
            select human_count
            from public.match_lobbies
            where region_id = %s and build_id = %s and closed_at is null
            order by created_at, id
            """,
            (region, build_id),
        ).fetchall()
    return sorted(int(row[0]) for row in rows)


def assert_two_players_share_one_lobby(database_url: str) -> None:
    results = claim_cohort(
        database_url,
        players=2,
        region="avrupa",
        build_id="concurrency-two-player",
    )
    lobby_ids = {lobby_id for lobby_id, _ in results}
    assert len(lobby_ids) == 1, f"simultaneous players split across lobbies: {results}"
    assert lobby_counts(
        database_url,
        region="avrupa",
        build_id="concurrency-two-player",
    ) == [2]


def assert_capacity_rolls_into_isolated_matches(database_url: str) -> None:
    results = claim_cohort(
        database_url,
        players=25,
        region="asya",
        build_id="concurrency-capacity",
    )
    distribution = Counter(lobby_id for lobby_id, _ in results)
    assert sorted(distribution.values()) == [5, 10, 10], distribution
    assert lobby_counts(
        database_url,
        region="asya",
        build_id="concurrency-capacity",
    ) == [5, 10, 10]


def assert_running_match_accepts_late_joiner(database_url: str) -> None:
    build_id = "concurrency-late-join"
    first_player = uuid.uuid4()
    first_lobby, _ = claim(
        database_url,
        barrier=None,
        region="auto",
        player_id=first_player,
        build_id=build_id,
    )
    with psycopg.connect(database_url, autocommit=True) as connection:
        connection.execute(
            """
            update public.match_lobbies
            set status = 'ready',
                request_id = %s,
                match_id = %s,
                server_id = %s
            where id = %s
            """,
            ("edgegap-running", uuid.uuid4(), uuid.uuid4(), first_lobby),
        )
    late_lobby, _ = claim(
        database_url,
        barrier=None,
        region="auto",
        player_id=uuid.uuid4(),
        build_id=build_id,
    )
    assert late_lobby == first_lobby, (first_lobby, late_lobby)
    assert lobby_counts(database_url, region="auto", build_id=build_id) == [2]


def assert_retries_are_idempotent(database_url: str) -> None:
    player_id = uuid.uuid4()
    first = claim(
        database_url,
        barrier=None,
        region="guney_amerika",
        player_id=player_id,
        build_id="concurrency-idempotent",
    )
    second = claim(
        database_url,
        barrier=None,
        region="guney_amerika",
        player_id=player_id,
        build_id="concurrency-idempotent",
    )
    assert first[0] == second[0], (first, second)
    assert lobby_counts(
        database_url,
        region="guney_amerika",
        build_id="concurrency-idempotent",
    ) == [1]


def assert_region_and_build_isolation(database_url: str) -> None:
    player_id = uuid.uuid4()
    base_lobby, _ = claim(
        database_url,
        barrier=None,
        region="avrupa",
        player_id=player_id,
        build_id="compatibility-v1",
    )
    other_build_lobby, _ = claim(
        database_url,
        barrier=None,
        region="avrupa",
        player_id=player_id,
        build_id="compatibility-v2",
    )
    other_region_lobby, _ = claim(
        database_url,
        barrier=None,
        region="asya",
        player_id=player_id,
        build_id="compatibility-v1",
    )
    assert len({base_lobby, other_build_lobby, other_region_lobby}) == 3


def main() -> int:
    database_url = parse_args().database_url
    install_schema(database_url)
    assert_two_players_share_one_lobby(database_url)
    assert_capacity_rolls_into_isolated_matches(database_url)
    assert_running_match_accepts_late_joiner(database_url)
    assert_retries_are_idempotent(database_url)
    assert_region_and_build_isolation(database_url)
    print("PASS shared matchmaking PostgreSQL concurrency contract")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
