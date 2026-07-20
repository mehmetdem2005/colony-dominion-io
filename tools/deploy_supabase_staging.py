#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys
from pathlib import Path
from typing import Any


def load_shared_deployer(root: Path):
    path = root / "tools" / "deploy_online_stack.py"
    spec = importlib.util.spec_from_file_location("colony_deploy_online_stack", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load shared deployer: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def extract_rows(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, list):
        return [row for row in value if isinstance(row, dict)]
    if not isinstance(value, dict):
        return []
    for key in ("result", "data", "rows"):
        nested = value.get(key)
        if isinstance(nested, list):
            return [row for row in nested if isinstance(row, dict)]
        if isinstance(nested, dict):
            rows = extract_rows(nested)
            if rows:
                return rows
    return []


def validate_migrations(root: Path) -> list[Path]:
    try:
        from pglast import parse_sql
    except ImportError as exc:
        raise RuntimeError("pglast is required for migration validation") from exc

    directory = root / "backend" / "supabase" / "migrations"
    migrations = sorted(directory.glob("*.sql"))
    if not migrations:
        raise RuntimeError(f"No migrations found in {directory}")
    for migration in migrations:
        sql = migration.read_text(encoding="utf-8")
        normalized = sql.strip().casefold()
        if not normalized.startswith("begin;") or not normalized.endswith("commit;"):
            raise RuntimeError(
                f"Migration {migration.name} must start with BEGIN and end with COMMIT"
            )
        try:
            parse_sql(sql)
        except Exception as exc:
            raise RuntimeError(f"Migration parse failed for {migration.name}: {exc}") from exc
    return migrations


def preflight(module, token: str, project) -> dict[str, str]:
    status = str(project.status).strip().upper()
    if status.startswith("INACTIVE") or status in {"PAUSED", "REMOVED"}:
        raise module.DeployError(
            f"Supabase project is not active: {project.name} ({project.status})"
        )
    result = module.http_json(
        "POST",
        f"{module.SUPABASE_API}/projects/{project.ref}/database/query/read-only",
        token=token,
        body={
            "query": (
                "select current_database()::text as database_name, "
                "current_user::text as database_user"
            ),
            "parameters": [],
        },
        timeout=60.0,
    )
    rows = extract_rows(result)
    if len(rows) != 1:
        raise module.DeployError(
            "Supabase Management API read-only query returned an unexpected response"
        )
    database_name = str(rows[0].get("database_name", "")).strip()
    database_user = str(rows[0].get("database_user", "")).strip()
    if not database_name or not database_user:
        raise module.DeployError("Supabase preflight returned incomplete database metadata")
    return {"database_name": database_name, "database_user": database_user}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-name",
        default=os.getenv("COLONY_PROJECT_NAME", "colony.io"),
    )
    parser.add_argument(
        "--project-ref",
        default=os.getenv("SUPABASE_PROJECT_REF", ""),
    )
    parser.add_argument("--environment", default="staging")
    parser.add_argument("--preflight-only", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(__file__).resolve().parents[1]
    module = load_shared_deployer(root)
    token = os.getenv("SUPABASE_ACCESS_TOKEN", "").strip()
    if not token:
        raise module.DeployError("SUPABASE_ACCESS_TOKEN is required")
    if args.environment != "staging":
        raise module.DeployError("This deployer is restricted to the staging environment")

    migrations = validate_migrations(root)
    projects = module.list_supabase_projects(token)
    project = module.select_project(projects, args.project_name, args.project_ref)
    print(
        f"[Supabase] Selected {project.name} "
        f"({project.ref}, {project.region}, {project.status})"
    )
    access = preflight(module, token, project)
    print(
        "[Supabase] Management API preflight passed "
        f"({access['database_name']}, {access['database_user']})"
    )
    publishable_key = module.get_publishable_key(token, project.ref)
    if args.preflight_only:
        print(f"[Supabase] Validated {len(migrations)} migration files")
        print("SUPABASE_PREFLIGHT_OK")
        return 0

    applied = module.run_supabase_migrations(root, token, project.ref)
    verification = module.verify_supabase_schema(token, project.ref)
    module.update_client_config(
        root,
        supabase_url=project.url,
        publishable_key=publishable_key,
        environment="staging",
    )
    report = {
        "status": "complete",
        "deployment_environment": "staging",
        "project_name_query": args.project_name,
        "supabase": {
            "project_ref": project.ref,
            "project_name": project.name,
            "region": project.region,
            "status": project.status,
            "url": project.url,
            "publishable_key_prefix": publishable_key[:16],
            "migrations_applied": applied,
            "migration_count": len(migrations),
            "management_preflight": access,
            "verification": verification,
        },
        "rivet": {"status": "blocked_provider_internal_error"},
    }
    report_path = module.write_report(root, report)
    print(f"[Supabase] Deployment report: {report_path}")
    print("SUPABASE_STAGING_SCHEMA_OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"SUPABASE_STAGING_DEPLOY_FAILED: {exc}", file=sys.stderr)
        raise SystemExit(2)
    finally:
        if "SUPABASE_ACCESS_TOKEN" in os.environ:
            os.environ["SUPABASE_ACCESS_TOKEN"] = ""
