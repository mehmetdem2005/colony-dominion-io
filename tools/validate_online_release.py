#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_BUILD = "PHASE-05.3-ONLINE-PRODUCTION-COMPLETION"
EXPECTED_PROTOCOL = 3


class ValidationFailure(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationFailure(message)


def validate() -> dict[str, object]:
    config = json.loads((ROOT / "config/backend_config.json").read_text(encoding="utf-8"))
    require(config.get("build_id") == EXPECTED_BUILD, "backend build id mismatch")
    require(config.get("protocol_version") == EXPECTED_PROTOCOL, "protocol version mismatch")

    protocol = (ROOT / "network/network_protocol.gd").read_text(encoding="utf-8")
    require("const VERSION: int = 3" in protocol, "GDScript protocol version mismatch")
    require("RECONNECT_GRACE_SECONDS: float = 60.0" in protocol, "reconnect grace mismatch")
    require("MAX_SNAPSHOT_ENTITIES: int = 128" in protocol, "snapshot budget mismatch")

    transport = (ROOT / "network/game_transport.gd").read_text(encoding="utf-8")
    for marker in (
        "DedicatedMatchStartGate",
        "GAME_SERVER_AUTH_TOKEN",
        "EXPECTED_PLAYERS",
        "clear_persisted_reconnect_session",
        "_rpc_match_ended",
    ):
        require(marker in transport, f"transport marker missing: {marker}")

    migrations = sorted((ROOT / "backend/supabase/migrations").glob("*.sql"))
    names = [path.name for path in migrations]
    require(len(names) == len(set(name.split("_", 1)[0] for name in names)), "duplicate migration version")
    require(names[-2:] == [
        "202607190004_ranked_schema.sql",
        "202607190005_authoritative_ranked_results.sql",
    ], "ranked migration order mismatch")
    ranked_sql = migrations[-1].read_text(encoding="utf-8").lower()
    for marker in (
        "pg_advisory_xact_lock",
        "rating_history",
        "to service_role",
        "p_ranked boolean",
        "ratings_processed_at",
    ):
        require(marker in ranked_sql, f"ranked SQL marker missing: {marker}")

    registry = (ROOT / "backend/rivet-control/src/registry.ts").read_text(encoding="utf-8")
    allocator = (ROOT / "backend/rivet-control/src/allocator.ts").read_text(encoding="utf-8")
    server = (ROOT / "backend/rivet-control/src/server.ts").read_text(encoding="utf-8")
    for marker in ("releaseMatch", "registerServerCredential", "queueTicketId"):
        require(marker in registry, f"registry lifecycle marker missing: {marker}")
    for marker in ("EXPECTED_PLAYERS", "GAME_SERVER_AUTH_TOKEN", "@rivet-gg/api"):
        require(marker in allocator, f"allocator marker missing: {marker}")
    for marker in ("authorizeServer", "/v1/internal/matches/result", "p_ranked"):
        require(marker in server, f"control server marker missing: {marker}")

    export_text = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    require('name="Dedicated Server"' in export_text, "dedicated export preset missing")
    require('permissions/internet=true' in export_text, "Android INTERNET permission missing")
    require("config/*.json,legal/*.json,legal/*.md" in export_text, "Android legal/config export filter missing")

    secret_patterns = (
        re.compile(r"cloud\.eyJ[A-Za-z0-9_.-]+"),
        re.compile(r"\bsbp_[A-Za-z0-9]{20,}"),
        re.compile(r"\bsb_secret_[A-Za-z0-9_-]{20,}"),
    )
    scanned = 0
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.name == "SHA256SUMS.txt":
            continue
        if any(part in {"node_modules", ".godot", "build"} for part in path.parts):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        scanned += 1
        for pattern in secret_patterns:
            require(pattern.search(text) is None, f"secret-like token found in {path.relative_to(ROOT)}")

    return {
        "ok": True,
        "build_id": EXPECTED_BUILD,
        "protocol_version": EXPECTED_PROTOCOL,
        "migrations": names,
        "text_files_scanned": scanned,
    }


def main() -> int:
    try:
        report = validate()
    except (ValidationFailure, json.JSONDecodeError, OSError) as exc:
        print(f"ONLINE_RELEASE_VALIDATION_FAILED: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
