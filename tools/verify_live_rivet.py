#!/usr/bin/env python3
"""Fail-closed smoke checks for the live Rivet control surface."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

CONFIG_PATH = Path("config/backend_config.json")
REPORT_PATH = Path("build/online-test/live-control-smoke.json")
EXPECTED_BUILD_ID = "PHASE-05.5-GOOGLE-BOT-BACKFILL"
EXPECTED_PROTOCOL_VERSION = 4
EXPECTED_REGION_ID = "eu"
EXPECTED_REGION_NAME = "Avrupa — Frankfurt"
EXPECTED_REGION_SHORT_NAME = "EU-FRA"
EXPECTED_BOT_BACKFILL_SECONDS = 30
MAX_WAIT_SECONDS = 1_200
POLL_INTERVAL_SECONDS = 10


def endpoint(base_url: str, path: str) -> str:
    parsed = urllib.parse.urlsplit(base_url)
    full_path = f"{parsed.path.rstrip('/')}/{path.lstrip('/')}"
    return urllib.parse.urlunsplit(
        (parsed.scheme, parsed.netloc, full_path, parsed.query, "")
    )


def get_json(base_url: str, path: str, timeout: int = 30) -> dict[str, Any]:
    request = urllib.request.Request(
        endpoint(base_url, path),
        headers={
            "Accept": "application/json",
            "Cache-Control": "no-cache",
            "User-Agent": "Colony-Live-05-5-Verification/1.0",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        if response.status != 200:
            raise RuntimeError(f"{path} returned HTTP {response.status}")
        payload = json.loads(response.read().decode("utf-8"))
    if not isinstance(payload, dict):
        raise RuntimeError(f"{path} returned a non-object JSON payload")
    return payload


def verify_auth_boundary(base_url: str, config: dict[str, Any], region_id: str) -> None:
    payload = json.dumps(
        {
            "player_id": "00000000-0000-4000-8000-000000000001",
            "display_name": "APKSmoke",
            "region_preference": "auto",
            "selected_region_id": region_id,
            "build_id": config["build_id"],
            "protocol_version": config["protocol_version"],
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        endpoint(base_url, "/v1/matchmaking/join"),
        data=payload,
        method="POST",
        headers={"Accept": "application/json", "Content-Type": "application/json"},
    )
    try:
        urllib.request.urlopen(request, timeout=30)
    except urllib.error.HTTPError as error:
        if error.code == 401:
            return
        raise RuntimeError(f"Auth boundary returned HTTP {error.code}") from error
    raise RuntimeError("Unauthenticated matchmaking request was accepted")


def current_runtime_state(base_url: str) -> dict[str, Any]:
    health = get_json(base_url, "/v1/health")
    service_config = get_json(base_url, "/v1/health/config")
    regions = get_json(base_url, "/v1/regions")
    if health.get("ok") is not True:
        raise RuntimeError(f"Rivet health failed: {health}")

    enabled = [
        region
        for region in regions.get("regions", [])
        if isinstance(region, dict) and bool(region.get("enabled"))
    ]
    limits = service_config.get("limits", {})
    checks = service_config.get("checks", {})
    return {
        "health": health,
        "service_config": service_config,
        "regions": regions,
        "enabled_regions": enabled,
        "ready": service_config.get("ready") is True,
        "build_configured": checks.get("supported_build_id") is True,
        "protocol_configured": checks.get("protocol_version") is True,
        "max_players": limits.get("max_players"),
        "bot_backfill_wait_seconds": limits.get("bot_backfill_wait_seconds"),
        "transport": limits.get("transport"),
    }


def runtime_matches_release(state: dict[str, Any]) -> bool:
    enabled = state["enabled_regions"]
    if len(enabled) != 1:
        return False
    region = enabled[0]
    probe_url = str(region.get("probe_url", ""))
    parsed_probe = urllib.parse.urlsplit(probe_url)
    return (
        state["ready"]
        and state["build_configured"]
        and state["protocol_configured"]
        and state["max_players"] == 10
        and state["bot_backfill_wait_seconds"] == EXPECTED_BOT_BACKFILL_SECONDS
        and state["transport"] == "rivet_websocket"
        and region.get("id") == EXPECTED_REGION_ID
        and region.get("display_name") == EXPECTED_REGION_NAME
        and region.get("short_name") == EXPECTED_REGION_SHORT_NAME
        and parsed_probe.scheme == "https"
        and parsed_probe.path.rstrip("/").endswith("/request/v1/health/ping")
        and bool(parsed_probe.query)
    )


def wait_for_release(base_url: str) -> dict[str, Any]:
    deadline = time.monotonic() + MAX_WAIT_SECONDS
    last_state: dict[str, Any] = {}
    last_error = "runtime check did not run"
    while time.monotonic() < deadline:
        try:
            last_state = current_runtime_state(base_url)
            if runtime_matches_release(last_state):
                return last_state
            last_error = json.dumps(last_state, ensure_ascii=False)
        except (OSError, RuntimeError, json.JSONDecodeError) as error:
            last_error = str(error)
        time.sleep(POLL_INTERVAL_SECONDS)
    raise RuntimeError(f"05.5 EU runtime did not become ready: {last_error}")


def verify_probe(region: dict[str, Any]) -> dict[str, Any]:
    probe_url = str(region.get("probe_url", ""))
    samples: list[int] = []
    for sample_index in range(4):
        separator = "&" if "?" in probe_url else "?"
        request_url = f"{probe_url}{separator}ci={int(time.time() * 1000)}&s={sample_index}"
        started = time.monotonic()
        request = urllib.request.Request(
            request_url,
            headers={"Accept": "application/json", "Cache-Control": "no-cache"},
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status != 200:
                raise RuntimeError(f"EU probe returned HTTP {response.status}")
            payload = json.loads(response.read().decode("utf-8"))
            if payload.get("ok") is not True:
                raise RuntimeError(f"EU probe returned invalid payload: {payload}")
        elapsed_ms = max(1, round((time.monotonic() - started) * 1000))
        if sample_index > 0:
            samples.append(elapsed_ms)
    samples.sort()
    return {
        "samples_ms": samples,
        "median_ms": samples[len(samples) // 2],
        "warmup_discarded": True,
    }


def main() -> int:
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    if not isinstance(config, dict):
        raise RuntimeError("Backend config must be a JSON object")
    if config.get("build_id") != EXPECTED_BUILD_ID:
        raise RuntimeError("APK build identity is not 05.5")
    if config.get("protocol_version") != EXPECTED_PROTOCOL_VERSION:
        raise RuntimeError("APK protocol identity is not version 4")
    base_url = str(config.get("rivet_control_base_url", "")).strip()
    if not base_url.startswith("https://"):
        raise RuntimeError("Rivet control URL must use HTTPS")

    state = wait_for_release(base_url)
    region = state["enabled_regions"][0]
    probe = verify_probe(region)
    verify_auth_boundary(base_url, config, EXPECTED_REGION_ID)

    report = {
        "health": True,
        "runtime_05_5_ready": True,
        "build_id": EXPECTED_BUILD_ID,
        "protocol_version": EXPECTED_PROTOCOL_VERSION,
        "enabled_regions": [EXPECTED_REGION_ID],
        "region_display_name": EXPECTED_REGION_NAME,
        "provider_region": "fra",
        "bot_backfill_wait_seconds": EXPECTED_BOT_BACKFILL_SECONDS,
        "query_safe_probe": True,
        "probe": probe,
        "auth_boundary": True,
    }
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
