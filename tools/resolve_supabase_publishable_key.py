#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


def required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"required environment variable is missing: {name}")
    return value


def score(item: Any) -> int:
    if not isinstance(item, dict):
        return -1
    key = str(item.get("api_key", "")).strip()
    key_type = str(item.get("type", "")).strip().lower()
    name = str(item.get("name", "")).strip().lower()
    prefix = str(item.get("prefix", "")).strip().lower()
    if not key:
        return -1
    if key.startswith("sb_secret_") or key_type == "secret":
        return -1
    if "service_role" in name or "service role" in name or "secret" in name:
        return -1
    if key_type == "publishable":
        return 100
    if key.startswith("sb_publishable_") or prefix.startswith("sb_publishable_"):
        return 95
    if name == "anon" or "anonymous" in name:
        return 90
    if key_type == "legacy" and key.count(".") == 2:
        return 80
    return -1


def fetch_keys(access_token: str, project_ref: str) -> list[dict[str, Any]]:
    request = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{project_ref}/api-keys?reveal=true",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Accept": "application/json",
            "User-Agent": "colony-release-key-resolver/1",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8", errors="replace"))
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Supabase Management API key lookup failed: {exc}") from exc
    if not isinstance(payload, list):
        raise RuntimeError("Supabase API key response is not a list")
    return [item for item in payload if isinstance(item, dict)]


def main() -> int:
    existing = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "").strip()
    source = "configured"
    if existing:
        selected = existing
    else:
        selected = ""
        candidates = sorted(
            ((score(item), item) for item in fetch_keys(required("SUPABASE_ACCESS_TOKEN"), required("SUPABASE_PROJECT_REF"))),
            key=lambda pair: pair[0],
            reverse=True,
        )
        if candidates and candidates[0][0] >= 0:
            selected = str(candidates[0][1].get("api_key", "")).strip()
            source = "management_api"

    if not selected:
        raise RuntimeError("no publishable or legacy anon Supabase API key was found")
    if selected.startswith("sb_secret_"):
        raise RuntimeError("refusing to select a Supabase secret API key")

    github_env = required("GITHUB_ENV")
    with open(github_env, "a", encoding="utf-8") as output:
        output.write(f"SUPABASE_PUBLISHABLE_KEY={selected}\n")
    print(f"::add-mask::{selected}")

    report_path = Path(os.environ.get("SUPABASE_KEY_REPORT", "build/rivet-staging/supabase-publishable-key.json"))
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(
            {
                "resolved": True,
                "source": source,
                "sha256_12": hashlib.sha256(selected.encode("utf-8")).hexdigest()[:12],
                "secret_key_rejected": True,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print("SUPABASE_PUBLISHABLE_KEY_READY=true")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"SUPABASE_PUBLISHABLE_KEY_RESOLUTION_FAILED: {exc}", file=sys.stderr)
        raise SystemExit(1)
