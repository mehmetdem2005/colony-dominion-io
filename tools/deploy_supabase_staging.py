#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sys
import urllib.parse
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

    auth_config = module.http_json(
        "GET",
        f"{module.SUPABASE_API}/projects/{project.ref}/config/auth",
        token=token,
        timeout=45.0,
    )
    if not isinstance(auth_config, dict):
        raise module.DeployError("Supabase Auth config preflight returned an unexpected response")
    return {
        "database_name": database_name,
        "database_user": database_user,
        "auth_site_url": str(auth_config.get("site_url", "")),
    }


def append_path_before_query(base_url: str, path: str) -> str:
    parsed = urllib.parse.urlsplit(base_url.strip())
    if parsed.scheme != "https" or not parsed.netloc:
        raise ValueError("Auth confirmation base URL must be HTTPS")
    base_path = parsed.path.rstrip("/")
    suffix = "/" + path.strip("/")
    return urllib.parse.urlunsplit(
        (parsed.scheme, parsed.netloc, f"{base_path}{suffix}", parsed.query, "")
    )


def load_confirmation_template(root: Path) -> str:
    path = root / "backend" / "supabase" / "email_templates" / "confirmation.html"
    if not path.is_file():
        raise RuntimeError(f"Confirmation email template is missing: {path}")
    content = path.read_text(encoding="utf-8").strip()
    if "{{ .ConfirmationURL }}" not in content:
        raise RuntimeError("Confirmation email template must use {{ .ConfirmationURL }}")
    if len(content) < 500:
        raise RuntimeError("Confirmation email template is unexpectedly short")
    return content


def parse_allow_list(value: Any) -> list[str]:
    items: list[str] = []
    for item in re.split(r"[,\n]", str(value or "")):
        normalized = item.strip()
        if normalized and normalized not in items:
            items.append(normalized)
    return items


def configure_auth_confirmation(
    module,
    root: Path,
    token: str,
    project_ref: str,
) -> dict[str, Any]:
    client_config_path = root / "config" / "backend_config.json"
    client_config = json.loads(client_config_path.read_text(encoding="utf-8"))
    control_base_url = str(client_config.get("rivet_control_base_url", "")).strip()
    confirmation_url = append_path_before_query(control_base_url, "/v1/auth/confirmed")
    if "localhost" in confirmation_url.casefold():
        raise module.DeployError("Production auth confirmation URL must not use localhost")

    current = module.http_json(
        "GET",
        f"{module.SUPABASE_API}/projects/{project_ref}/config/auth",
        token=token,
        timeout=45.0,
    )
    if not isinstance(current, dict):
        raise module.DeployError("Could not read current Supabase Auth configuration")

    allow_list = [
        item
        for item in parse_allow_list(current.get("uri_allow_list", ""))
        if "localhost" not in item.casefold() and "127.0.0.1" not in item
    ]
    if confirmation_url not in allow_list:
        allow_list.append(confirmation_url)

    # Redirect safety is critical and must not be coupled to optional email branding.
    # Supabase free-tier projects using the default mail provider reject template writes.
    module.http_json(
        "PATCH",
        f"{module.SUPABASE_API}/projects/{project_ref}/config/auth",
        token=token,
        body={
            "site_url": confirmation_url,
            "uri_allow_list": ",".join(allow_list),
        },
        timeout=60.0,
    )

    redirect_verified = module.http_json(
        "GET",
        f"{module.SUPABASE_API}/projects/{project_ref}/config/auth",
        token=token,
        timeout=45.0,
    )
    if not isinstance(redirect_verified, dict):
        raise module.DeployError("Could not verify Supabase Auth redirect configuration")
    verified_site_url = str(redirect_verified.get("site_url", "")).strip()
    verified_allow_list = parse_allow_list(redirect_verified.get("uri_allow_list", ""))
    if verified_site_url != confirmation_url:
        raise module.DeployError("Supabase Auth site URL verification failed")
    if confirmation_url not in verified_allow_list:
        raise module.DeployError("Supabase Auth redirect allow-list verification failed")
    if any(
        "localhost" in item.casefold() or "127.0.0.1" in item
        for item in verified_allow_list
    ):
        raise module.DeployError("Supabase Auth redirect allow-list still contains localhost")

    template = load_confirmation_template(root)
    template_status = "deployed"
    template_deployed = False
    subject_deployed = False
    try:
        module.http_json(
            "PATCH",
            f"{module.SUPABASE_API}/projects/{project_ref}/config/auth",
            token=token,
            body={
                "mailer_subjects_confirmation": (
                    "Colony Dominion.io — E-posta adresini doğrula"
                ),
                "mailer_templates_confirmation_content": template,
            },
            timeout=60.0,
        )
        branded_verified = module.http_json(
            "GET",
            f"{module.SUPABASE_API}/projects/{project_ref}/config/auth",
            token=token,
            timeout=45.0,
        )
        if not isinstance(branded_verified, dict):
            raise module.DeployError("Could not verify Supabase confirmation template")
        verified_template = str(
            branded_verified.get("mailer_templates_confirmation_content", "")
        )
        verified_subject = str(branded_verified.get("mailer_subjects_confirmation", ""))
        if "{{ .ConfirmationURL }}" not in verified_template:
            raise module.DeployError("Supabase confirmation email template verification failed")
        if "E-POSTAYI DOĞRULA" not in verified_template:
            raise module.DeployError("Supabase confirmation email action verification failed")
        if "Colony Dominion.io" not in verified_subject:
            raise module.DeployError("Supabase confirmation email subject verification failed")
        template_deployed = True
        subject_deployed = True
    except Exception as exc:
        message = str(exc)
        normalized = message.casefold()
        free_tier_restriction = (
            "email template modification is not available for free tier projects"
            in normalized
            and "default email provider" in normalized
        )
        if not free_tier_restriction:
            raise
        template_status = "blocked_free_tier_default_provider"
        print(
            "[Supabase] Confirmation email branding was not applied because the "
            "project uses the free-tier default email provider. Redirect safety "
            "was applied successfully."
        )

    return {
        "site_url": verified_site_url,
        "redirect_allowlisted": True,
        "localhost_removed": True,
        "confirmation_template": template_deployed,
        "confirmation_subject": subject_deployed,
        "template_status": template_status,
    }


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
    load_confirmation_template(root)
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
        print(f"[Supabase] Current Auth site URL: {access['auth_site_url']}")
        print(f"[Supabase] Validated {len(migrations)} migration files")
        print("SUPABASE_PREFLIGHT_OK")
        return 0

    applied = module.run_supabase_migrations(root, token, project.ref)
    verification = module.verify_supabase_schema(token, project.ref)
    auth_verification = configure_auth_confirmation(module, root, token, project.ref)
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
            "auth_confirmation": auth_verification,
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
