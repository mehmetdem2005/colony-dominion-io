#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def finding(level: str, code: str, message: str, path: str = "") -> dict[str, str]:
    return {"level": level, "code": code, "message": message, "path": path}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    findings: list[dict[str, str]] = []

    try:
        from pglast import parse_sql
    except ImportError as exc:
        raise SystemExit(f"pglast is required: {exc}")

    migration_dir = root / "backend" / "supabase" / "migrations"
    migrations = sorted(migration_dir.glob("*.sql"))
    if not migrations:
        findings.append(finding("error", "MIGRATIONS_MISSING", "No migration files were found", str(migration_dir)))
    for migration in migrations:
        sql = migration.read_text(encoding="utf-8")
        normalized = sql.strip().casefold()
        if not normalized.startswith("begin;") or not normalized.endswith("commit;"):
            findings.append(finding("error", "MIGRATION_NOT_TRANSACTIONAL", "Migration is not wrapped in BEGIN/COMMIT", str(migration)))
        try:
            parse_sql(sql)
        except Exception as exc:
            findings.append(finding("error", "MIGRATION_PARSE_ERROR", str(exc), str(migration)))

    all_sql = "\n".join(path.read_text(encoding="utf-8") for path in migrations)
    if re.search(r"'[^']*-draft'[^;]*true\s*,\s*true", all_sql, re.IGNORECASE | re.DOTALL):
        findings.append(finding(
            "warning",
            "ACTIVE_DRAFT_LEGAL_DOCUMENTS",
            "Draft legal documents are active. Keep this only in staging; production requires final legal versions.",
            "backend/supabase/migrations/202607190002_legal_documents_seed.sql",
        ))
    if re.search(r"grant\s+select\s*,\s*insert\s*,\s*update\s*,\s*delete\s+on\s+public\.account_deletion_requests", all_sql, re.IGNORECASE):
        findings.append(finding(
            "warning",
            "DELETION_REQUESTS_ARE_DELETABLE",
            "Clients can delete account-deletion request records, weakening the compliance audit trail.",
            "backend/supabase/migrations/202607190001_initial_online_schema.sql",
        ))
    if re.search(r"create\s+policy\s+seasons_read_active[\s\S]*?using\s*\(true\)", all_sql, re.IGNORECASE):
        findings.append(finding(
            "warning",
            "SEASON_POLICY_TOO_BROAD",
            "seasons_read_active currently exposes every season rather than only active seasons.",
            "backend/supabase/migrations/202607190001_initial_online_schema.sql",
        ))

    wrapper = root / "tools" / "deploy_online_stack.sh"
    wrapper_text = wrapper.read_text(encoding="utf-8") if wrapper.is_file() else ""
    if "SKIP_RIVET" not in wrapper_text or "--skip-rivet" not in wrapper_text:
        findings.append(finding("error", "SECRET_GATING_MISSING", "Rivet secrets are not gated by --skip-rivet", str(wrapper)))
    if "-t 0" not in wrapper_text:
        findings.append(finding("error", "CI_PROMPT_UNSAFE", "Wrapper may try to prompt for secrets in non-interactive CI", str(wrapper)))

    workflow = root / ".github" / "workflows" / "deploy-supabase-staging.yml"
    workflow_text = workflow.read_text(encoding="utf-8") if workflow.is_file() else ""
    if "SUPABASE_SECRET_KEY" in workflow_text:
        findings.append(finding("error", "EXCESS_SECRET_SCOPE", "Supabase-only workflow receives an unnecessary backend secret", str(workflow)))
    if not re.search(
        r"deploy_supabase_staging\.py[\s\\]+--project-name[\s\S]*?--preflight-only",
        workflow_text,
    ):
        findings.append(finding("error", "PREFLIGHT_MISSING", "Supabase workflow lacks a non-mutating API preflight", str(workflow)))

    config = root / "config" / "backend_config.json"
    config_text = config.read_text(encoding="utf-8") if config.is_file() else ""
    if re.search(r"sb_secret_|service_role|cloud_api_", config_text, re.IGNORECASE):
        findings.append(finding("error", "CLIENT_SECRET_PRESENT", "A backend secret appears in client configuration", str(config)))

    deployer = root / "tools" / "deploy_online_stack.py"
    deployer_text = deployer.read_text(encoding="utf-8") if deployer.is_file() else ""
    if "rivet-cli@latest" in deployer_text:
        findings.append(finding(
            "warning",
            "OBSOLETE_RIVET_CLI_PATH",
            "The legacy full-stack deployer still references rivet-cli; keep the Rivet path disabled until it is migrated to @rivetkit/cli.",
            str(deployer),
        ))

    allocator = root / "backend" / "rivet-control" / "src" / "allocator.ts"
    allocator_text = allocator.read_text(encoding="utf-8") if allocator.is_file() else ""
    if "@rivet-gg/api" in allocator_text and "buildTags" in allocator_text:
        findings.append(finding(
            "warning",
            "LEGACY_RIVET_GAME_SERVER_ARCHITECTURE",
            "Direct allocation depends on the legacy Game Cloud buildTags/actors API. Current Rivet Compute uses @rivetkit/cli runner pools; use an external allocator or obtain Rivet compatibility confirmation before production.",
            str(allocator),
        ))

    errors = [item for item in findings if item["level"] == "error"]
    warnings = [item for item in findings if item["level"] == "warning"]
    report = {
        "status": "failed" if errors else "passed_with_warnings" if warnings else "passed",
        "error_count": len(errors),
        "warning_count": len(warnings),
        "migration_count": len(migrations),
        "findings": findings,
    }
    output = root / "deployment" / "deployment_audit.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print("===== ONLINE DEPLOYMENT AUDIT =====")
    for item in findings:
        location = f" [{item['path']}]" if item["path"] else ""
        print(f"{item['level'].upper()} {item['code']}{location}: {item['message']}")
    print(f"AUDIT_STATUS={report['status']} errors={len(errors)} warnings={len(warnings)}")
    return 1 if errors and args.strict else 0


if __name__ == "__main__":
    raise SystemExit(main())
