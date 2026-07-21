#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

CLOUD_API = "https://cloud-api.rivet.dev"
TRANSIENT_HTTP = {429, 500, 502, 503, 504}
REQUIRED_RUNTIME_ENV = (
    "NODE_ENV",
    "SUPABASE_URL",
    "SUPABASE_SECRET_KEY",
    "SUPPORTED_BUILD_ID",
    "PROTOCOL_VERSION",
    "MIN_PLAYERS",
    "MAX_PLAYERS",
    "QUEUE_TTL_SECONDS",
    "REGIONS_JSON",
    "RIVET_STARTUP_CANARY",
)


class DeploymentError(RuntimeError):
    pass


@dataclass(frozen=True)
class ApiResponse:
    status: int
    body: Any


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise DeploymentError(f"required environment variable is missing: {name}")
    return value


def encode(value: str) -> str:
    return urllib.parse.quote(value, safe="")


def parse_json(raw: bytes, *, context: str) -> Any:
    text = raw.decode("utf-8", errors="replace")
    if not text.strip():
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise DeploymentError(f"{context} returned invalid JSON") from exc


def request_api(
    token: str,
    method: str,
    path: str,
    *,
    body: dict[str, Any] | None = None,
    allow_not_found: bool = False,
    max_attempts: int = 8,
) -> ApiResponse:
    url = f"{CLOUD_API}/{path.lstrip('/')}"
    encoded_body = None if body is None else json.dumps(body, separators=(",", ":")).encode("utf-8")
    last_error = "request did not run"

    for attempt in range(1, max_attempts + 1):
        request = urllib.request.Request(
            url,
            data=encoded_body,
            method=method,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
                "Content-Type": "application/json",
                "User-Agent": "colony-rivet-direct-deployer/1",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read()
                return ApiResponse(response.status, parse_json(raw, context=path))
        except urllib.error.HTTPError as exc:
            raw = exc.read()
            if exc.code == 404 and allow_not_found:
                return ApiResponse(404, parse_json(raw, context=path) if raw else None)
            message = raw.decode("utf-8", errors="replace")[:1000]
            last_error = f"HTTP {exc.code}: {message}"
            if exc.code not in TRANSIENT_HTTP or attempt == max_attempts:
                raise DeploymentError(f"Cloud API {method} {path} failed: {last_error}") from exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last_error = str(exc)
            if attempt == max_attempts:
                raise DeploymentError(f"Cloud API {method} {path} failed: {last_error}") from exc

        delay = min(3 * (2 ** (attempt - 1)), 30)
        print(f"RIVET_DIRECT_RETRY attempt={attempt}/{max_attempts} delay={delay}s reason={last_error}")
        time.sleep(delay)

    raise DeploymentError(f"Cloud API request exhausted retries: {last_error}")


def resolve_namespace(token: str, project: str, organization: str, requested: str) -> str:
    direct_path = f"projects/{encode(project)}/namespaces/{encode(requested)}?org={encode(organization)}"
    direct = request_api(token, "GET", direct_path, allow_not_found=True)
    if direct.status == 200 and isinstance(direct.body, dict):
        namespace = direct.body.get("namespace")
        if isinstance(namespace, dict) and namespace.get("name"):
            return str(namespace["name"])

    cursor: str | None = None
    for _ in range(100):
        query = f"org={encode(organization)}&limit=100"
        if cursor:
            query += f"&cursor={encode(cursor)}"
        listed = request_api(token, "GET", f"projects/{encode(project)}/namespaces?{query}")
        if not isinstance(listed.body, dict):
            break
        for item in listed.body.get("namespaces", []):
            if not isinstance(item, dict):
                continue
            name = str(item.get("name", ""))
            display_name = str(item.get("displayName", ""))
            if name == requested or display_name.casefold() == requested.casefold():
                return name
        pagination = listed.body.get("pagination")
        cursor = str(pagination.get("cursor", "")) if isinstance(pagination, dict) else ""
        if not cursor:
            break
    raise DeploymentError(f"Rivet namespace was not found: {requested}")


def pool_from_response(body: Any) -> dict[str, Any]:
    if not isinstance(body, dict):
        return {}
    value = body.get("managedPool", body.get("managed_pool"))
    return value if isinstance(value, dict) else {}


def build_pool_body(image_repository: str, image_tag: str) -> dict[str, Any]:
    environment = {name: require_env(name) for name in REQUIRED_RUNTIME_ENV}
    return {
        "displayName": "Default",
        "image": {"repository": image_repository, "tag": image_tag},
        "environment": environment,
        "runnerConfig": {
            "maxConcurrentActors": 3,
            "drainGracePeriod": 60,
            "drainOnVersionUpgrade": True,
        },
        "resources": {
            "cpu": 2,
            "memory": "2Gi",
            "minScale": 0,
            "maxScale": 4,
            "instanceRequestConcurrency": 80,
        },
    }


def write_report(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Directly upsert a Rivet managed pool without the CLI pre-enable call")
    parser.add_argument("--namespace", default="staging")
    parser.add_argument("--image-repository", required=True)
    parser.add_argument("--image-tag", required=True)
    parser.add_argument("--report", type=Path, default=Path("build/rivet-staging/direct-deploy.json"))
    parser.add_argument("--timeout-seconds", type=int, default=600)
    args = parser.parse_args()

    started_at = datetime.now(timezone.utc)
    token = require_env("RIVET_CLOUD_TOKEN")
    inspect = request_api(token, "GET", "tokens/api/inspect")
    if not isinstance(inspect.body, dict):
        raise DeploymentError("token inspect returned an invalid response")
    project = str(inspect.body.get("project", "")).strip()
    organization = str(inspect.body.get("organization", "")).strip()
    if not project or not organization:
        raise DeploymentError("token inspect did not return project and organization")

    namespace = resolve_namespace(token, project, organization, args.namespace)
    endpoint = (
        f"projects/{encode(project)}/namespaces/{encode(namespace)}"
        f"/managed-pools/default?org={encode(organization)}"
    )
    body = build_pool_body(args.image_repository, args.image_tag)

    print(
        "RIVET_DIRECT_UPSERT "
        f"project={project} namespace={namespace} image={args.image_repository}:{args.image_tag}"
    )
    request_api(token, "PUT", endpoint, body=body, max_attempts=10)

    deadline = time.monotonic() + max(args.timeout_seconds, 60)
    last_status = "unknown"
    last_error: Any = None
    final_pool: dict[str, Any] = {}
    while time.monotonic() < deadline:
        response = request_api(token, "GET", endpoint, max_attempts=5)
        pool = pool_from_response(response.body)
        final_pool = pool
        last_status = str(pool.get("status", "unknown"))
        last_error = pool.get("error")
        print(f"RIVET_DIRECT_POOL_STATUS status={last_status}")
        if last_status == "ready":
            break
        if last_status == "error":
            raise DeploymentError(f"managed pool entered error state: {last_error}")
        time.sleep(3)
    else:
        raise DeploymentError(f"timed out waiting for managed pool readiness; last_status={last_status}")

    config = final_pool.get("config") if isinstance(final_pool.get("config"), dict) else {}
    resources = config.get("resources") if isinstance(config.get("resources"), dict) else {}
    image = config.get("image") if isinstance(config.get("image"), dict) else {}
    report = {
        "success": True,
        "provider": "rivet_only",
        "deployment_method": "direct_cloud_api_managed_pool_upsert",
        "project": project,
        "organization": organization,
        "namespace": namespace,
        "managed_pool_status": last_status,
        "image": {
            "repository": image.get("repository", args.image_repository),
            "tag": image.get("tag", args.image_tag),
        },
        "resources": {
            "cpu": resources.get("cpu", 2),
            "memory": resources.get("memory", "2Gi"),
            "minScale": resources.get("minScale", 0),
            "maxScale": resources.get("maxScale", 4),
            "instanceRequestConcurrency": resources.get("instanceRequestConcurrency", 80),
        },
        "environment_keys": sorted(REQUIRED_RUNTIME_ENV),
        "started_at": started_at.isoformat(),
        "completed_at": datetime.now(timezone.utc).isoformat(),
    }
    write_report(args.report, report)
    print("RIVET_DIRECT_DEPLOY_READY=true")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except DeploymentError as exc:
        print(f"RIVET_DIRECT_DEPLOY_FAILED: {exc}", file=sys.stderr)
        raise SystemExit(1)
