#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_BUILD = "PHASE-05.5-GOOGLE-BOT-BACKFILL"
EXPECTED_PROTOCOL = 4
EXPECTED_PLACEMENT_TARGETS = {"auto", "tr", "eu-se", "eu-central"}


class ValidationFailure(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationFailure(message)


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require_markers(path: str, markers: tuple[str, ...]) -> str:
    text = read(path)
    for marker in markers:
        require(marker in text, f"{path} marker missing: {marker}")
    return text


def function_body(source: str, function_name: str) -> str:
    start = source.find(f"func {function_name}")
    require(start >= 0, f"function missing: {function_name}")
    end = source.find("\nfunc ", start + 5)
    return source[start:] if end < 0 else source[start:end]


def validate_config() -> tuple[dict[str, object], list[str]]:
    config = json.loads(read("config/backend_config.json"))
    require(config.get("build_id") == EXPECTED_BUILD, "backend build id mismatch")
    require(config.get("protocol_version") == EXPECTED_PROTOCOL, "protocol version mismatch")
    require(str(config.get("supabase_url", "")).startswith("https://"), "Supabase URL missing")
    require(bool(config.get("supabase_publishable_key")), "Supabase publishable key missing")
    config_text = json.dumps(config).lower()
    for forbidden in ("edgegap_api_token", "service_role", "sb_secret_", "database_password"):
        require(forbidden not in config_text, f"client config contains secret marker: {forbidden}")

    regions = [
        row
        for row in config.get("regions", [])
        if isinstance(row, dict) and row.get("enabled") is True
    ]
    region_ids = {str(row.get("id", "")) for row in regions}
    require(
        EXPECTED_PLACEMENT_TARGETS.issubset(region_ids),
        f"Edgegap placement targets missing: {sorted(EXPECTED_PLACEMENT_TARGETS - region_ids)}",
    )
    require(
        all(row.get("placement_only") is True for row in regions),
        "Edgegap manual targets must be marked placement_only",
    )
    return config, sorted(region_ids)


def validate_transport_and_presentation() -> None:
    protocol = require_markers(
        "network/network_protocol.gd",
        (
            "const VERSION: int = 4",
            "TRANSPORT_ENET",
            "RECONNECT_GRACE_SECONDS: float = 60.0",
            "MAX_SNAPSHOT_ENTITIES: int = 128",
            "MAX_INTERPOLATION_DELAY_MSEC: int = 85",
        ),
    )
    require("INTERPOLATION_DELAY_MSEC: int = 110" not in protocol, "legacy 110 ms delay remains")

    require_markers(
        "network/rivet_game_transport.gd",
        (
            "ENetMultiplayerPeer",
            "NETWORK_TRANSPORT",
            "_configure_server_population",
            "create_server",
            "create_client",
            "_process_reconnect",
        ),
    )
    transport = require_markers(
        "network/game_transport.gd",
        (
            "EXPECTED_JOIN_TICKET",
            "EXPECTED_PLAYER_ID",
            "_constant_time_equal",
            "_consumed_join_ticket_hashes",
            "_median_sample",
            "_rpc_receive_snapshot",
        ),
    )
    require(
        "snapshot_received.emit(snapshot.duplicate(true))" not in transport,
        "snapshot receive path deep-copies the swarm",
    )

    require_markers(
        "gameplay/presentation/colony_visual_catalog.gd",
        ("TEAM_COLORS", "configure_unit_sprite", "configure_nest_sprite"),
    )
    for path in (
        "gameplay/units/unit.gd",
        "gameplay/colony/colony_controller.gd",
        "gameplay/network/network_entity_proxy.gd",
    ):
        require("ColonyVisualCatalog" in read(path), f"{path} bypasses shared visual catalog")
    proxy = read("gameplay/network/network_entity_proxy.gd")
    require(
        "queue_redraw" not in function_body(proxy, "_physics_process"),
        "network proxy redraws every physics frame",
    )
    online_scene = read("scenes/online_game.tscn")
    require("res://scenes/ui/hud.tscn" in online_scene, "online game does not use shared HUD")
    require(not (ROOT / "ui/online_match_hud.gd").exists(), "duplicate online HUD remains")
    require_markers(
        "ui/hud.gd",
        ("bind_online", "apply_online_player_state", "set_lifecycle_state"),
    )
    require_markers(
        "gameplay/network/online_match_client.gd",
        ("_camera_anchor == anchor", "get_minimap_snapshot", "PROXY_SCENE"),
    )


def validate_edgegap() -> None:
    client = require_markers(
        "network/edgegap_matchmaking_client.gd",
        (
            '"player_id": player_id.strip_edges()',
            '"region_preference": preferred_id',
            '"selected_region_id": selected_id',
            "region_short_name",
        ),
    )
    require("EDGEGAP_API_TOKEN" not in client, "Edgegap token name leaked into game client")

    matchmaking = require_markers(
        "backend/supabase/functions/matchmaking/index.ts",
        (
            "https://api.edgegap.com/v1",
            "authenticatedUserId",
            "player_identity_mismatch",
            "REGION_TARGETS",
            "ip_list",
            "body.location",
            "skip_telemetry",
            "HUMAN_PLAYER_COUNT",
            "BOT_COUNT",
            "RANKED_MATCH",
            "EXPECTED_JOIN_TICKET",
            "EXPECTED_PLAYER_ID",
            "is_hidden: true",
        ),
    )
    require(
        "DEV_ACCEPT_JOIN_TICKETS" not in matchmaking,
        "production Edgegap deployment enables development ticket acceptance",
    )
    require_markers(
        "deploy/edgegap/Dockerfile",
        ("EXPOSE 20000/udp", "colony-dominion-server.x86_64", "--headless"),
    )
    require_markers(
        ".github/workflows/build-game-server-image.yml",
        ("deploy/edgegap/Dockerfile", "ghcr.io", "colony-dominion-server"),
    )


def validate_auth_and_storage() -> list[str]:
    migrations = sorted((ROOT / "backend/supabase/migrations").glob("*.sql"))
    names = [path.name for path in migrations]
    require(names, "Supabase migrations missing")
    require(
        len(names) == len(set(name.split("_", 1)[0] for name in names)),
        "duplicate migration version",
    )
    required_migrations = {
        "202607190004_ranked_schema.sql",
        "202607190005_authoritative_ranked_results.sql",
        "202607210006_google_oauth_handoffs.sql",
        "202607220007_google_oauth_pkce_handoffs.sql",
    }
    require(required_migrations.issubset(names), "production migration set incomplete")
    ranked_sql = read("backend/supabase/migrations/202607190005_authoritative_ranked_results.sql")
    for marker in ("pg_advisory_xact_lock", "rating_history", "ratings_processed_at"):
        require(marker in ranked_sql, f"ranked SQL marker missing: {marker}")
    require_markers(
        "backend/supabase/functions/oauth-google-handoff/index.ts",
        ("SUPABASE_SERVICE_ROLE_KEY", "oauth_handoffs", "pkce", "auth_code"),
    )
    require_markers(
        "network/supabase_oauth_handoff.gd",
        ("Crypto.new()", "OS.shell_open", "code_challenge", "sign_in_pkce_code"),
    )
    auth_panel = require_markers(
        "ui/auth_panel.gd",
        ("GOOGLE İLE DEVAM ET", "OnlineServices.sign_in_google"),
    )
    for forbidden in ("sign_in_email", "sign_up_email", "resend_signup_confirmation"):
        require(forbidden not in auth_panel, f"Google-only auth UI contains {forbidden}")
    return names


def validate_project_and_exports() -> None:
    project = read("project.godot")
    require(
        'GameTransport="*res://network/rivet_game_transport.gd"' in project,
        "direct ENet compatibility transport autoload missing",
    )
    require(
        'OnlineServices="*res://autoload/rivet_online_services.gd"' in project,
        "Edgegap assignment validator autoload missing",
    )
    require("EdgegapMatchmakingClient" in read("autoload/online_services.gd"), "Edgegap client unwired")
    export_text = read("export_presets.cfg")
    for marker in (
        'name="Android"',
        'name="Dedicated Server"',
        "architectures/arm64-v8a=true",
        "permissions/internet=true",
        "config/*.json,legal/*.json,legal/*.md",
    ):
        require(marker in export_text, f"export contract missing: {marker}")


def scan_for_embedded_secrets() -> int:
    patterns = (
        re.compile(r"cloud\.eyJ[A-Za-z0-9_.-]+"),
        re.compile(r"\bcloud_api_[A-Za-z0-9._~+/=-]{20,}"),
        re.compile(r"\bsbp_[A-Za-z0-9]{20,}"),
        re.compile(r"\bsb_secret_[A-Za-z0-9_-]{20,}"),
        re.compile(r"\begp_[A-Za-z0-9_-]{20,}"),
    )
    scanned = 0
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.name == "SHA256SUMS.txt":
            continue
        if any(part in {"node_modules", ".godot", ".git", "build"} for part in path.parts):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        scanned += 1
        for pattern in patterns:
            require(pattern.search(text) is None, f"secret-like token found in {path.relative_to(ROOT)}")
    return scanned


def validate() -> dict[str, object]:
    config, regions = validate_config()
    validate_transport_and_presentation()
    validate_edgegap()
    migrations = validate_auth_and_storage()
    validate_project_and_exports()
    scanned = scan_for_embedded_secrets()
    return {
        "ok": True,
        "build_id": config["build_id"],
        "protocol_version": config["protocol_version"],
        "transport": "edgegap_enet_udp",
        "placement_targets": regions,
        "max_players": 10,
        "shared_online_offline_hud": True,
        "shared_unit_assets": True,
        "single_use_join_ticket": True,
        "google_oauth_flow": "pkce",
        "migrations": migrations,
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
