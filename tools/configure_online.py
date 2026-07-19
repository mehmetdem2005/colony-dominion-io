#!/usr/bin/env python3
"""Writes client-safe online configuration. Never accepts backend secret keys."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib.parse import urlparse


def valid_https(value: str) -> bool:
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.netloc)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--supabase-url", required=True)
    parser.add_argument("--supabase-publishable-key", required=True)
    parser.add_argument("--rivet-control-url", required=True)
    parser.add_argument(
        "--output",
        default="config/backend_config.json",
        help="Project-relative output path",
    )
    parser.add_argument("--environment", default="production", choices=["development", "staging", "production"])
    args = parser.parse_args()

    if not valid_https(args.supabase_url):
        raise SystemExit("SUPABASE URL must use HTTPS")
    if not args.supabase_publishable_key.startswith(("sb_publishable_", "eyJ")):
        raise SystemExit("Expected a Supabase publishable key (or legacy anon key), never a secret/service_role key")
    if args.supabase_publishable_key.startswith(("sb_secret_", "service_role")):
        raise SystemExit("Refusing to place a Supabase secret/service_role key in the game client")
    if not valid_https(args.rivet_control_url):
        raise SystemExit("Rivet control URL must use HTTPS")

    output = Path(args.output)
    existing = json.loads(output.read_text(encoding="utf-8")) if output.exists() else {}
    existing.update(
        {
            "environment": args.environment,
            "supabase_url": args.supabase_url.rstrip("/"),
            "supabase_publishable_key": args.supabase_publishable_key.strip(),
            "rivet_control_base_url": args.rivet_control_url.rstrip("/"),
        }
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(existing, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Client-safe configuration written to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
