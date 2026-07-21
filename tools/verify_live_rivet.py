#!/usr/bin/env python3
"""Fail-closed smoke checks for the live Rivet control surface."""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

CONFIG_PATH = Path("config/backend_config.json")
REPORT_PATH = Path("build/online-test/live-control-smoke.json")


def endpoint(base_url: str, path: str) -> str:
    parsed = urllib.parse.urlsplit(base_url)
    full_path = f"{parsed.path.rstrip('/')}/{path.lstrip('/')}"
    return urllib.parse.urlunsplit(
        (parsed.scheme, parsed.netloc, full_path, parsed.query, "")
    )


def get_json(base_url: str, path: str) -> dict[str, Any]:
    request = urllib.request.Request(
        endpoint(base_url, path),
        headers={"Accept": "application/json", "Cache-Control": "no-cache"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
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


def main() -> int:
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    if not isinstance(config, dict):
        raise RuntimeError("Backend config must be a JSON object")
    base_url = str(config.get("rivet_control_base_url", "")).strip()
    if not base_url.startswith("https://"):
        raise RuntimeError("Rivet control URL must use HTTPS")

    health = get_json(base_url, "/v1/health")
    regions = get_json(base_url, "/v1/regions")
    if health.get("ok") is not True:
        raise RuntimeError(f"Rivet health failed: {health}")

    enabled_regions = [
        str(region.get("id", ""))
        for region in regions.get("regions", [])
        if isinstance(region, dict) and bool(region.get("enabled"))
    ]
    enabled_regions = [region_id for region_id in enabled_regions if region_id]
    if not enabled_regions:
        raise RuntimeError(f"No enabled Rivet region: {regions}")

    verify_auth_boundary(base_url, config, enabled_regions[0])
    report = {
        "health": True,
        "enabled_regions": enabled_regions,
        "auth_boundary": True,
        "build_id": config.get("build_id"),
        "protocol_version": config.get("protocol_version"),
    }
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
