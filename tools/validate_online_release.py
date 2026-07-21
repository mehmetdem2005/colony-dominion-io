#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_BUILD = "PHASE-05.4-RIVET-FULL-ONLINE"
EXPECTED_PROTOCOL = 4


class ValidationFailure(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationFailure(message)


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require_markers(path: str, markers: tuple[str, ...]) -> None:
    text = read(path)
    for marker in markers:
        require(marker in text, f"{path} marker missing: {marker}")


def validate() -> dict[str, object]:
    config = json.loads(read("config/backend_config.json"))
    require(config.get("build_id") == EXPECTED_BUILD, "backend build id mismatch")
    require(config.get("protocol_version") == EXPECTED_PROTOCOL, "protocol version mismatch")

    protocol = read("network/network_protocol.gd")
    require("const VERSION: int = 4" in protocol, "GDScript protocol version mismatch")
    require("TRANSPORT_WEBSOCKET" in protocol, "WebSocket transport contract missing")
    require("RECONNECT_GRACE_SECONDS: float = 60.0" in protocol, "reconnect grace mismatch")
    require("MAX_SNAPSHOT_ENTITIES: int = 128" in protocol, "snapshot budget mismatch")

    require_markers(
        "network/rivet_game_transport.gd",
        (
            "WebSocketMultiplayerPeer",
            "NETWORK_TRANSPORT",
            "create_server",
            "create_client",
            "_process_reconnect",
        ),
    )
    require_markers(
        "network/game_transport.gd",
        (
            "DedicatedMatchStartGate",
            "GAME_SERVER_AUTH_TOKEN",
            "EXPECTED_PLAYERS",
            "clear_persisted_reconnect_session",
            "_rpc_match_ended",
        ),
    )

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

    require_markers(
        "backend/rivet-control/src/registry.ts",
        ("releaseMatch", "registerServerCredential", "queueTicketId"),
    )
    require_markers(
        "backend/rivet-control/src/runtime-registry.ts",
        (
            "matchmaker",
            "gameServer",
            "controlApi",
            "maxIncomingMessageSize",
            "maxOutgoingMessageSize",
        ),
    )
    require_markers(
        "backend/rivet-control/src/control-api-actor.ts",
        (
            "onRequest",
            "x-colony-control-gateway",
            "/v1/matchmaking/join",
            "control_plane_unavailable",
        ),
    )
    require("/v1/internal/" not in read("backend/rivet-control/src/control-api-actor.ts"), "internal routes exposed by public actor")
    require_markers(
        "backend/rivet-control/src/public-control-gateway.ts",
        (
            "PUBLIC_CONTROL_ACTOR_KEY",
            "getGatewayUrl",
            "RIVET_PUBLIC_CONTROL_GATEWAY_READY",
            "health_verified",
        ),
    )
    require_markers(
        "backend/rivet-control/src/bootstrap.ts",
        ("ensurePublicControlGateway", "runStartupCanary", "RIVET_FULL_ONLINE_BOOTSTRAP_FAILED"),
    )
    require_markers(
        "backend/rivet-control/src/game-server-actor.ts",
        (
            "spawn(",
            "GODOT_PCK_PATH",
            "onWebSocket",
            "waitForGodotReady",
            "stopRuntime",
            "c.destroy()",
        ),
    )
    require_markers(
        "backend/rivet-control/src/rivet-native-allocator.ts",
        ("gameServer.create", "getGatewayUrl", "websocketUrl", "MAX_PLAYERS = 10"),
    )
    require_markers(
        "backend/rivet-control/src/server-full-online.ts",
        (
            "allocateRivetGameServer",
            "runtimeRegistry.handler",
            "Rivet full-online",
            "maxPlayers",
        ),
    )
    require_markers(
        "backend/rivet-control/src/startup-canary.ts",
        ("RIVET_GAME_ACTOR_CANARY_OK", "webSocket", "shutdown"),
    )

    dockerfile = read("backend/rivet-control/Dockerfile")
    for marker in (
        "GODOT_VERSION=4.6.3",
        "GODOT_PCK_PATH=/app/game/colony-dominion-server.pck",
        "COPY build/server/colony-dominion-server.pck",
        "dist/bootstrap.js",
    ):
        require(marker in dockerfile, f"full-online Docker marker missing: {marker}")

    project = read("project.godot")
    require('GameTransport="*res://network/rivet_game_transport.gd"' in project, "Rivet transport autoload missing")
    require('OnlineServices="*res://autoload/rivet_online_services.gd"' in project, "Rivet online services autoload missing")

    export_text = read("export_presets.cfg")
    require('name="Android"' in export_text, "Android export preset missing")
    require('name="Dedicated Server"' in export_text, "dedicated export preset missing")
    require('architectures/arm64-v8a=true' in export_text, "Android arm64 architecture missing")
    require('permissions/internet=true' in export_text, "Android INTERNET permission missing")
    require("config/*.json,legal/*.json,legal/*.md" in export_text, "Android legal/config export filter missing")
    require('version/name="0.5.4"' in export_text, "Android version mismatch")

    deploy_workflow = read(".github/workflows/deploy-rivet-control-staging.yml")
    for marker in (
        "SUPABASE_PUBLISHABLE_KEY",
        "RIVET_PUBLIC_CONTROL_GATEWAY_READY",
        "rivet_control_base_url",
        "--export-debug \"Android\"",
        "colony-dominion-rivet-staging.apk",
        "FULL_END_TO_END_RELEASE_READY=true",
    ):
        require(marker in deploy_workflow, f"deployment workflow marker missing: {marker}")

    forbidden_paths = (
        ROOT / "deployment/oracle",
        ROOT / "backend/external-allocator",
    )
    for path in forbidden_paths:
        require(not path.exists(), f"forbidden external-hosting path exists: {path.relative_to(ROOT)}")

    secret_patterns = (
        re.compile(r"cloud\.eyJ[A-Za-z0-9_.-]+"),
        re.compile(r"\bcloud_api_[A-Za-z0-9._~+/=-]{20,}"),
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
        "transport": "rivet_websocket",
        "public_control_gateway": True,
        "android_staging_artifact": True,
        "max_players": 10,
        "migrations": names,
        "text_files_scanned": scanned,
        "external_hosting": False,
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
