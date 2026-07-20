#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${REPO:-mehmetdem2005/colony-dominion-io}"
BRANCH="${BRANCH:-main}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-build/provisioning}"
SUPABASE_WORKFLOW="deploy-supabase-staging.yml"
RIVET_WORKFLOW="deploy-rivet-control-staging.yml"
LAST_RUN_ID=""

log() {
  printf '\n[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"
}

for command_name in git gh jq curl; do
  require_command "$command_name"
done

gh auth status >/dev/null 2>&1 || die "GitHub CLI authentication is not active. Run: gh auth login"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "Run this inside the colony-dominion-io Git repository"
cd "$ROOT"

if ! git diff --quiet || ! git diff --cached --quiet; then
  die "Tracked local changes exist. Commit or stash them before provisioning."
fi

log "Synchronizing $REPO:$BRANCH"
git pull --ff-only origin "$BRANCH"
HEAD_SHA="$(git rev-parse HEAD)"
printf 'HEAD=%s\n' "$HEAD_SHA"

collect_secret_names() {
  {
    gh secret list --repo "$REPO" --json name --jq '.[].name' 2>/dev/null || true
    gh secret list --repo "$REPO" --env "$ENVIRONMENT" --json name --jq '.[].name' 2>/dev/null || true
  } | sed '/^$/d' | sort -u
}

collect_variable_names() {
  {
    gh variable list --repo "$REPO" --json name --jq '.[].name' 2>/dev/null || true
    gh variable list --repo "$REPO" --env "$ENVIRONMENT" --json name --jq '.[].name' 2>/dev/null || true
  } | sed '/^$/d' | sort -u
}

SECRET_NAMES="$(collect_secret_names)"
VARIABLE_NAMES="$(collect_variable_names)"

require_named_value() {
  local category="$1"
  local names="$2"
  local required_name="$3"
  if ! grep -Fxq "$required_name" <<<"$names"; then
    die "$category is missing: $required_name"
  fi
}

log "Checking GitHub staging configuration names without reading secret values"
require_named_value "Secret" "$SECRET_NAMES" "SUPABASE_ACCESS_TOKEN"
require_named_value "Secret" "$SECRET_NAMES" "SUPABASE_SECRET_KEY"
require_named_value "Secret" "$SECRET_NAMES" "RIVET_CLOUD_TOKEN"
require_named_value "Variable" "$VARIABLE_NAMES" "SUPABASE_PROJECT_REF"
printf 'Required staging secret and variable names are present.\n'

for workflow in "$SUPABASE_WORKFLOW" "$RIVET_WORKFLOW"; do
  gh workflow view "$workflow" --repo "$REPO" >/dev/null 2>&1 \
    || die "Workflow is not available: $workflow"
done

latest_workflow_run_id() {
  local workflow="$1"
  gh run list \
    --repo "$REPO" \
    --workflow "$workflow" \
    --branch "$BRANCH" \
    --event workflow_dispatch \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId // empty'
}

dispatch_and_wait() {
  local workflow="$1"
  shift
  local before_id=""
  local candidate=""

  before_id="$(latest_workflow_run_id "$workflow" 2>/dev/null || true)"
  log "Dispatching $workflow"
  gh workflow run "$workflow" --repo "$REPO" --ref "$BRANCH" "$@"

  for _ in $(seq 1 30); do
    sleep 2
    candidate="$(latest_workflow_run_id "$workflow" 2>/dev/null || true)"
    if [[ -n "$candidate" && "$candidate" != "$before_id" ]]; then
      LAST_RUN_ID="$candidate"
      break
    fi
  done

  [[ -n "$LAST_RUN_ID" ]] || die "Could not resolve the new run ID for $workflow"
  printf 'RUN_ID=%s\n' "$LAST_RUN_ID"

  if ! gh run watch "$LAST_RUN_ID" --repo "$REPO" --exit-status; then
    printf '\n===== FAILED STEP LOG =====\n' >&2
    gh run view "$LAST_RUN_ID" --repo "$REPO" --log-failed 2>/dev/null | tail -n 300 >&2 || true
    die "$workflow failed"
  fi

  gh run view "$LAST_RUN_ID" --repo "$REPO"
}

download_artifact() {
  local run_id="$1"
  local artifact_name="$2"
  local destination="$3"

  rm -rf "$destination"
  mkdir -p "$destination"

  for _ in $(seq 1 6); do
    if gh run download "$run_id" \
      --repo "$REPO" \
      --name "$artifact_name" \
      --dir "$destination"; then
      return 0
    fi
    sleep 3
  done
  die "Could not download artifact $artifact_name from run $run_id"
}

log "Applying and verifying the Supabase staging schema"
LAST_RUN_ID=""
dispatch_and_wait "$SUPABASE_WORKFLOW"
SUPABASE_RUN_ID="$LAST_RUN_ID"
SUPABASE_ARTIFACT_DIR="$ARTIFACT_ROOT/supabase-$SUPABASE_RUN_ID"
download_artifact "$SUPABASE_RUN_ID" "colony-supabase-staging" "$SUPABASE_ARTIFACT_DIR"
SUPABASE_REPORT="$(find "$SUPABASE_ARTIFACT_DIR" -type f -name last_deployment.json -print -quit)"
[[ -n "$SUPABASE_REPORT" ]] || die "Supabase deployment report is missing from the artifact"

jq -e '
  .status == "complete" and
  .deployment_environment == "staging" and
  (.supabase.verification.verified_table_count >= 12) and
  (.supabase.verification.authoritative_result_function == true) and
  (.supabase.verification.leaderboard_function == true) and
  (.supabase.verification.ranked_summary_function == true) and
  ((.supabase.migrations_applied | length) >= 5)
' "$SUPABASE_REPORT" >/dev/null || die "Supabase artifact verification failed"

SUPABASE_PROJECT_REF="$(jq -er '.supabase.project_ref' "$SUPABASE_REPORT")"
SUPABASE_URL="$(jq -er '.supabase.url' "$SUPABASE_REPORT")"
printf 'SUPABASE_STAGING_READY=true\nSUPABASE_PROJECT_REF=%s\nSUPABASE_URL=%s\n' \
  "$SUPABASE_PROJECT_REF" "$SUPABASE_URL"

log "Deploying and verifying the Rivet Compute staging control plane"
LAST_RUN_ID=""
dispatch_and_wait "$RIVET_WORKFLOW" -f confirmation=DEPLOY-RIVET-STAGING
RIVET_RUN_ID="$LAST_RUN_ID"
RIVET_ARTIFACT_DIR="$ARTIFACT_ROOT/rivet-$RIVET_RUN_ID"
download_artifact "$RIVET_RUN_ID" "rivet-control-staging" "$RIVET_ARTIFACT_DIR"
RIVET_REPORT="$(find "$RIVET_ARTIFACT_DIR" -type f -name deployment-report.json -print -quit)"
[[ -n "$RIVET_REPORT" ]] || die "Rivet deployment report is missing from the artifact"

jq -e '
  .environment == "staging" and
  .control_plane_live == true and
  .supabase_schema_ready == true and
  .game_server_allocator_ready == false and
  .full_online_ready == false
' "$RIVET_REPORT" >/dev/null || die "Rivet control-plane artifact verification failed"

CONTROL_URL="$(jq -er '.rivet_control_base_url' "$RIVET_REPORT")"
for endpoint in /v1/health /v1/health/config /v1/regions; do
  curl --fail --silent --show-error \
    --retry 5 --retry-delay 2 --retry-all-errors \
    "$CONTROL_URL$endpoint" >/dev/null
done

printf '\n===== PROVISIONING RESULT =====\n'
printf 'SUPABASE_STAGING_READY=true\n'
printf 'RIVET_CONTROL_STAGING_READY=true\n'
printf 'RIVET_CONTROL_URL=%s\n' "$CONTROL_URL"
printf 'GAME_SERVER_ALLOCATOR_READY=false\n'
printf 'FULL_ONLINE_READY=false\n'
printf 'SUPABASE_RUN_ID=%s\n' "$SUPABASE_RUN_ID"
printf 'RIVET_RUN_ID=%s\n' "$RIVET_RUN_ID"
printf 'ARTIFACT_ROOT=%s\n' "$ARTIFACT_ROOT"
printf 'PROVISIONING_COMPLETED\n'
