#!/usr/bin/env python3
"""Deploy Colony Dominion's Supabase schema and Rivet control plane.

Secrets are read only from environment variables and are never written to disk.
Public deployment metadata is written to deployment/last_deployment.json.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

SUPABASE_API = "https://api.supabase.com/v1"
DEFAULT_PROJECT_NAME = "colony.io"
DEFAULT_NAMESPACE = "production"
TOKEN_ENV_NAMES = (
    "SUPABASE_ACCESS_TOKEN",
    "RIVET_CLOUD_TOKEN",
)


class DeployError(RuntimeError):
    pass


@dataclass(frozen=True)
class SupabaseProject:
    ref: str
    name: str
    region: str
    status: str

    @property
    def url(self) -> str:
        return f"https://{self.ref}.supabase.co"


def normalize_name(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.casefold())


def redact(value: str) -> str:
    if not value:
        return ""
    if len(value) <= 10:
        return "***"
    return f"{value[:4]}…{value[-4:]}"


def http_json(
    method: str,
    url: str,
    *,
    token: str | None = None,
    body: Any | None = None,
    timeout: float = 45.0,
    retries: int = 3,
) -> Any:
    payload = None
    headers = {
        "accept": "application/json",
        "user-agent": "colony-dominion-deployer/05.3.0",
    }
    if token:
        headers["authorization"] = f"Bearer {token}"
    if body is not None:
        payload = json.dumps(body).encode("utf-8")
        headers["content-type"] = "application/json"

    last_error: Exception | None = None
    for attempt in range(retries):
        request = urllib.request.Request(
            url,
            data=payload,
            method=method.upper(),
            headers=headers,
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read()
                if not raw:
                    return None
                content_type = response.headers.get("content-type", "")
                if "json" in content_type or raw[:1] in (b"{", b"["):
                    return json.loads(raw.decode("utf-8"))
                return raw.decode("utf-8", errors="replace")
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            if exc.code == 429 or 500 <= exc.code < 600:
                last_error = DeployError(
                    f"HTTP {exc.code} from {url}: {detail[:500]}"
                )
            else:
                raise DeployError(
                    f"HTTP {exc.code} from {url}: {detail[:1000]}"
                ) from exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last_error = exc
        if attempt + 1 < retries:
            time.sleep(1.5 * (2**attempt))
    raise DeployError(f"Request failed for {url}: {last_error}")


def list_supabase_projects(token: str) -> list[SupabaseProject]:
    result = http_json("GET", f"{SUPABASE_API}/projects", token=token)
    if not isinstance(result, list):
        raise DeployError("Supabase project list returned an unexpected response")
    projects: list[SupabaseProject] = []
    for item in result:
        if not isinstance(item, dict):
            continue
        ref = str(item.get("ref", "")).strip()
        name = str(item.get("name", "")).strip()
        if not ref or not name:
            continue
        projects.append(
            SupabaseProject(
                ref=ref,
                name=name,
                region=str(item.get("region", "")),
                status=str(item.get("status", "")),
            )
        )
    return projects


def select_project(
    projects: list[SupabaseProject], project_name: str, project_ref: str = ""
) -> SupabaseProject:
    if project_ref:
        matches = [project for project in projects if project.ref == project_ref]
    else:
        target = normalize_name(project_name)
        exact = [project for project in projects if normalize_name(project.name) == target]
        if exact:
            matches = exact
        else:
            matches = [
                project
                for project in projects
                if target in normalize_name(project.name)
                or normalize_name(project.name) in target
            ]
    if len(matches) == 1:
        return matches[0]
    visible = ", ".join(f"{p.name} ({p.ref})" for p in projects) or "none"
    if not matches:
        raise DeployError(
            f"No Supabase project matched {project_name!r}. Accessible projects: {visible}"
        )
    raise DeployError(
        "Multiple Supabase projects matched. Set SUPABASE_PROJECT_REF explicitly: "
        + ", ".join(f"{p.name} ({p.ref})" for p in matches)
    )


def get_publishable_key(token: str, project_ref: str) -> str:
    result = http_json(
        "GET",
        f"{SUPABASE_API}/projects/{project_ref}/api-keys?reveal=true",
        token=token,
    )
    if not isinstance(result, list):
        raise DeployError("Supabase API key list returned an unexpected response")

    publishable: list[str] = []
    legacy_anon: list[str] = []
    for item in result:
        if not isinstance(item, dict):
            continue
        key = str(item.get("api_key", "")).strip()
        key_type = str(item.get("type", "")).casefold()
        name = str(item.get("name", "")).casefold()
        if not key:
            continue
        if key.startswith("sb_secret_") or "service_role" in name:
            continue
        if key.startswith("sb_publishable_") or key_type == "publishable":
            publishable.append(key)
        elif name == "anon" or (key.startswith("eyJ") and "anon" in name):
            legacy_anon.append(key)

    candidates = publishable or legacy_anon
    if not candidates:
        raise DeployError(
            "No client-safe Supabase publishable/anon key was available. "
            "Do not substitute a secret or service_role key."
        )
    return candidates[0]


def run_supabase_migrations(root: Path, token: str, project_ref: str) -> list[str]:
    migration_dir = root / "backend" / "supabase" / "migrations"
    migrations = sorted(migration_dir.glob("*.sql"))
    if not migrations:
        raise DeployError(f"No migrations found in {migration_dir}")
    applied: list[str] = []
    for migration in migrations:
        sql = migration.read_text(encoding="utf-8")
        if not sql.strip():
            continue
        print(f"[Supabase] Applying {migration.name}")
        http_json(
            "POST",
            f"{SUPABASE_API}/projects/{project_ref}/database/query",
            token=token,
            body={"query": sql, "read_only": False},
            timeout=120.0,
        )
        applied.append(migration.name)
    return applied


def verify_supabase_schema(token: str, project_ref: str) -> dict[str, Any]:
    expected_tables = {
        "profiles",
        "player_preferences",
        "seasons",
        "player_ratings",
        "legal_documents",
        "legal_acceptances",
        "matches",
        "match_participants",
        "player_reports",
        "bans",
        "account_deletion_requests",
        "rating_history",
    }
    query = """
with expected(table_name) as (
  values
    ('profiles'),('player_preferences'),('seasons'),('player_ratings'),
    ('legal_documents'),('legal_acceptances'),('matches'),
    ('match_participants'),('player_reports'),('bans'),
    ('account_deletion_requests'),('rating_history')
)
select
  expected.table_name,
  coalesce(c.relrowsecurity, false) as rls_enabled,
  to_regprocedure(
    'public.record_authoritative_match_result(uuid,text,text,text,integer,timestamptz,timestamptz,text,jsonb,boolean)'
  ) is not null as result_function_exists,
  to_regprocedure('public.get_season_leaderboard(integer)') is not null as leaderboard_function_exists,
  to_regprocedure('public.get_my_ranked_summary()') is not null as ranked_summary_function_exists
from expected
left join pg_catalog.pg_namespace n on n.nspname = 'public'
left join pg_catalog.pg_class c
  on c.relnamespace = n.oid
 and c.relname = expected.table_name
 and c.relkind = 'r'
order by expected.table_name;
""".strip()
    result = http_json(
        "POST",
        f"{SUPABASE_API}/projects/{project_ref}/database/query/read-only",
        token=token,
        body={"query": query, "parameters": []},
        timeout=60.0,
    )
    rows: list[dict[str, Any]] = []
    if isinstance(result, list):
        rows = [row for row in result if isinstance(row, dict)]
    elif isinstance(result, dict):
        for key in ("result", "data", "rows"):
            value = result.get(key)
            if isinstance(value, list):
                rows = [row for row in value if isinstance(row, dict)]
                break
    actual_tables = {str(row.get("table_name", "")) for row in rows}
    missing_tables = sorted(expected_tables - actual_tables)
    if missing_tables:
        raise DeployError(f"Supabase schema verification missing tables: {missing_tables}")
    missing_rls = [
        str(row.get("table_name", ""))
        for row in rows
        if not bool(row.get("rls_enabled"))
    ]
    if missing_rls:
        raise DeployError(f"RLS verification failed for tables: {missing_rls}")
    if not rows or not all(bool(row.get("result_function_exists")) for row in rows):
        raise DeployError("Authoritative match-result RPC function is missing")
    if not all(bool(row.get("leaderboard_function_exists")) for row in rows):
        raise DeployError("Season leaderboard RPC function is missing")
    if not all(bool(row.get("ranked_summary_function_exists")) for row in rows):
        raise DeployError("Ranked summary RPC function is missing")
    return {
        "rows": rows,
        "verified_table_count": len(actual_tables),
        "authoritative_result_function": True,
        "leaderboard_function": True,
        "ranked_summary_function": True,
    }


def update_client_config(
    root: Path,
    *,
    supabase_url: str,
    publishable_key: str,
    rivet_control_url: str = "",
    environment: str = "production",
) -> None:
    config_path = root / "config" / "backend_config.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    config.update(
        {
            "environment": environment,
            "supabase_url": supabase_url.rstrip("/"),
            "supabase_publishable_key": publishable_key,
        }
    )
    if rivet_control_url:
        config["rivet_control_base_url"] = rivet_control_url.rstrip("/")
    config_path.write_text(
        json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def run_command(
    command: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
    capture: bool = False,
) -> str:
    safe_display = [
        "***"
        if "cloud." in part or "sbp_" in part
        else part
        for part in command
    ]
    print("+", " ".join(safe_display))
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        check=False,
    )
    output = result.stdout or ""
    if capture and output:
        print(output)
    if result.returncode != 0:
        raise DeployError(f"Command failed with exit code {result.returncode}: {command[0]}")
    return output


def extract_public_url(output: str) -> str:
    urls = re.findall(r"https://[A-Za-z0-9][A-Za-z0-9._:-]*(?:/[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]*)?", output)
    preferred = [url.rstrip(".,)") for url in urls if "rivet" in url.casefold()]
    return preferred[-1] if preferred else (urls[-1].rstrip(".,)") if urls else "")


def deploy_rivet_control(
    root: Path,
    *,
    cloud_token: str,
    allocator_cloud_token: str,
    supabase_url: str,
    supabase_secret_key: str,
    namespace: str,
    project: str,
    environment: str,
    game_server_build_tag: str,
    organization: str,
    allocator_url: str,
    public_control_url: str,
    regions_json: str,
) -> str:
    control = root / "backend" / "rivet-control"
    for binary in ("node", "npm", "docker"):
        if shutil.which(binary) is None:
            raise DeployError(f"{binary} is required for Rivet deployment")

    if (control / "package-lock.json").exists():
        run_command(["npm", "ci", "--no-audit", "--no-fund"], cwd=control)
    else:
        run_command(["npm", "install", "--no-audit", "--no-fund"], cwd=control)
    run_command(["npm", "run", "typecheck"], cwd=control)
    run_command(["npm", "run", "build"], cwd=control)

    build_id, protocol_version = read_client_protocol(root)
    env = os.environ.copy()
    env["RIVET_CLOUD_TOKEN"] = cloud_token
    env["SUPABASE_URL"] = supabase_url
    env["SUPABASE_SECRET_KEY"] = supabase_secret_key
    env["SUPPORTED_BUILD_ID"] = build_id
    env["PROTOCOL_VERSION"] = str(protocol_version)
    env["MIN_PLAYERS"] = "2"
    env["MAX_PLAYERS"] = "10"
    env["QUEUE_TTL_SECONDS"] = "120"
    env["RIVET_PROJECT"] = project
    env["RIVET_ENVIRONMENT"] = environment
    env["RIVET_GAME_SERVER_BUILD_TAG"] = game_server_build_tag
    if public_control_url:
        env["PUBLIC_CONTROL_BASE_URL"] = public_control_url.rstrip("/")
    if allocator_url:
        env["RIVET_ALLOCATOR_URL"] = allocator_url.rstrip("/")
    else:
        env["RIVET_ALLOCATOR_CLOUD_TOKEN"] = allocator_cloud_token
    if regions_json:
        parsed_regions = json.loads(regions_json)
        if not isinstance(parsed_regions, list):
            raise DeployError("REGIONS_JSON must contain a JSON array")
        env["REGIONS_JSON"] = json.dumps(parsed_regions, separators=(",", ":"))
    # Rivet's documented deployment command reads rivet.json from this directory.
    # Runtime secrets remain environment/secret-store values and never CLI arguments.
    command = ["npx", "--yes", "rivet-cli@latest", "deploy"]
    output = run_command(command, cwd=control, env=env, capture=True)
    endpoint = extract_public_url(output)
    if not endpoint:
        raise DeployError(
            "Rivet deployment completed but no public URL could be parsed. "
            "Copy the endpoint from the CLI output and rerun with --rivet-control-url."
        )
    return endpoint.rstrip("/")


def read_client_protocol(root: Path) -> tuple[str, int]:
    config = json.loads((root / "config" / "backend_config.json").read_text(encoding="utf-8"))
    build_id = str(config.get("build_id", "PHASE-05.3-ONLINE-PRODUCTION-COMPLETION"))
    protocol_version = int(config.get("protocol_version", 3))
    return build_id, protocol_version


def verify_public_endpoint(base_url: str) -> dict[str, Any]:
    health = http_json("GET", f"{base_url.rstrip('/')}/v1/health", timeout=30.0)
    configuration = http_json(
        "GET", f"{base_url.rstrip('/')}/v1/health/config", timeout=30.0
    )
    regions = http_json("GET", f"{base_url.rstrip('/')}/v1/regions", timeout=30.0)
    if not isinstance(health, dict) or not bool(health.get("ok")):
        raise DeployError("Rivet control-plane health check failed")
    if not isinstance(configuration, dict) or not bool(configuration.get("ready")):
        raise DeployError(
            f"Rivet runtime configuration is incomplete: {configuration}"
        )
    if not isinstance(regions, dict) or not isinstance(regions.get("regions"), list):
        raise DeployError("Rivet region catalog check failed")
    return {
        "health": health,
        "configuration": configuration,
        "region_count": len(regions["regions"]),
    }


def write_report(root: Path, report: dict[str, Any]) -> Path:
    path = root / "deployment" / "last_deployment.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-name", default=os.getenv("COLONY_PROJECT_NAME", DEFAULT_PROJECT_NAME))
    parser.add_argument("--project-ref", default=os.getenv("SUPABASE_PROJECT_REF", ""))
    parser.add_argument("--namespace", default=os.getenv("RIVET_NAMESPACE", DEFAULT_NAMESPACE))
    parser.add_argument("--rivet-project", default=os.getenv("RIVET_PROJECT", ""))
    parser.add_argument("--rivet-org", default=os.getenv("RIVET_ORG", ""))
    parser.add_argument("--rivet-environment", default=os.getenv("RIVET_ENVIRONMENT", "production"))
    parser.add_argument("--game-server-build-tag", default=os.getenv("RIVET_GAME_SERVER_BUILD_TAG", "colony-server-05-3"))
    parser.add_argument("--rivet-control-url", default=os.getenv("RIVET_CONTROL_URL", ""))
    parser.add_argument("--allocator-url", default=os.getenv("RIVET_ALLOCATOR_URL", ""))
    parser.add_argument("--regions-json", default=os.getenv("REGIONS_JSON", ""))
    parser.add_argument("--skip-supabase", action="store_true")
    parser.add_argument("--skip-rivet", action="store_true")
    parser.add_argument("--no-migrations", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(__file__).resolve().parents[1]
    supabase_token = os.getenv("SUPABASE_ACCESS_TOKEN", "").strip()
    rivet_token = os.getenv("RIVET_CLOUD_TOKEN", "").strip()
    allocator_cloud_token = os.getenv("RIVET_ALLOCATOR_CLOUD_TOKEN", "").strip()
    supabase_secret_key = os.getenv("SUPABASE_SECRET_KEY", "").strip()

    report: dict[str, Any] = {
        "status": "started",
        "project_name_query": args.project_name,
        "rivet_namespace": args.namespace,
        "supabase": {},
        "rivet": {},
    }

    supabase_project: SupabaseProject | None = None
    publishable_key = ""
    if not args.skip_supabase:
        if not supabase_token:
            raise DeployError("SUPABASE_ACCESS_TOKEN is required")
        print(f"[Supabase] Token loaded: {redact(supabase_token)}")
        projects = list_supabase_projects(supabase_token)
        supabase_project = select_project(projects, args.project_name, args.project_ref)
        print(
            f"[Supabase] Selected {supabase_project.name} "
            f"({supabase_project.ref}, {supabase_project.region}, {supabase_project.status})"
        )
        publishable_key = get_publishable_key(supabase_token, supabase_project.ref)
        applied: list[str] = []
        if not args.no_migrations:
            applied = run_supabase_migrations(root, supabase_token, supabase_project.ref)
        verification = verify_supabase_schema(supabase_token, supabase_project.ref)
        update_client_config(
            root,
            supabase_url=supabase_project.url,
            publishable_key=publishable_key,
            rivet_control_url=args.rivet_control_url,
        )
        report["supabase"] = {
            "project_ref": supabase_project.ref,
            "project_name": supabase_project.name,
            "region": supabase_project.region,
            "status": supabase_project.status,
            "url": supabase_project.url,
            "publishable_key_prefix": publishable_key[:16],
            "migrations_applied": applied,
            "verification": verification,
        }

    control_url = args.rivet_control_url.rstrip("/")
    if not args.skip_rivet:
        if not rivet_token:
            raise DeployError("RIVET_CLOUD_TOKEN is required")
        if not supabase_project:
            config = json.loads((root / "config" / "backend_config.json").read_text(encoding="utf-8"))
            supabase_url = str(config.get("supabase_url", ""))
            if not supabase_url:
                raise DeployError("Supabase URL is required before Rivet deployment")
        else:
            supabase_url = supabase_project.url
        if not supabase_secret_key:
            raise DeployError("SUPABASE_SECRET_KEY is required for authoritative match-result writes")
        if not args.allocator_url and not allocator_cloud_token:
            raise DeployError(
                "RIVET_ALLOCATOR_CLOUD_TOKEN is required for direct container allocation; "
                "use a scoped runtime token, not the broad deployment token"
            )
        if not args.allocator_url and (not args.rivet_project or not args.rivet_environment):
            raise DeployError("RIVET_PROJECT and RIVET_ENVIRONMENT are required for direct allocation")
        print(f"[Rivet] Deployment token loaded: {redact(rivet_token)}")
        if not control_url:
            control_url = deploy_rivet_control(
                root,
                cloud_token=rivet_token,
                allocator_cloud_token=allocator_cloud_token,
                supabase_url=supabase_url,
                supabase_secret_key=supabase_secret_key,
                namespace=args.namespace,
                project=args.rivet_project,
                environment=args.rivet_environment,
                game_server_build_tag=args.game_server_build_tag,
                organization=args.rivet_org,
                allocator_url=args.allocator_url,
                public_control_url="",
                regions_json=args.regions_json,
            )
            if not args.allocator_url:
                control_url = deploy_rivet_control(
                    root,
                    cloud_token=rivet_token,
                    allocator_cloud_token=allocator_cloud_token,
                    supabase_url=supabase_url,
                    supabase_secret_key=supabase_secret_key,
                    namespace=args.namespace,
                    project=args.rivet_project,
                    environment=args.rivet_environment,
                    game_server_build_tag=args.game_server_build_tag,
                    organization=args.rivet_org,
                    allocator_url="",
                    public_control_url=control_url,
                    regions_json=args.regions_json,
                )
        endpoint_check = verify_public_endpoint(control_url)
        if not publishable_key:
            config = json.loads((root / "config" / "backend_config.json").read_text(encoding="utf-8"))
            publishable_key = str(config.get("supabase_publishable_key", ""))
        update_client_config(
            root,
            supabase_url=supabase_url,
            publishable_key=publishable_key,
            rivet_control_url=control_url,
        )
        report["rivet"] = {
            "control_url": control_url,
            "namespace": args.namespace,
            "verification": endpoint_check,
        }

    report["status"] = "complete"
    report_path = write_report(root, report)
    print(f"Deployment complete. Public report: {report_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except DeployError as exc:
        print(f"DEPLOYMENT FAILED: {exc}", file=sys.stderr)
        raise SystemExit(2)
    finally:
        for name in (*TOKEN_ENV_NAMES, "RIVET_ALLOCATOR_CLOUD_TOKEN", "SUPABASE_SECRET_KEY"):
            if name in os.environ:
                os.environ[name] = ""
