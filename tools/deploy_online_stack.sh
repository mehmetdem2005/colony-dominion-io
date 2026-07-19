#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

read_secret_if_missing() {
  local variable_name="$1"
  local prompt="$2"
  if [[ -z "${!variable_name:-}" ]]; then
    read -rsp "$prompt" value
    echo
    printf -v "$variable_name" '%s' "$value"
    export "$variable_name"
  fi
}

read_secret_if_missing SUPABASE_ACCESS_TOKEN "Supabase temporary Personal Access Token: "
read_secret_if_missing RIVET_CLOUD_TOKEN "Rivet deployment token: "
read_secret_if_missing SUPABASE_SECRET_KEY "Supabase backend secret key (never the client key): "
if [[ -z "${RIVET_ALLOCATOR_URL:-}" ]]; then
  read_secret_if_missing RIVET_ALLOCATOR_CLOUD_TOKEN \
    "Rivet scoped allocator runtime token: "
fi

cleanup() {
  unset SUPABASE_ACCESS_TOKEN RIVET_CLOUD_TOKEN SUPABASE_SECRET_KEY \
    RIVET_ALLOCATOR_CLOUD_TOKEN value
}
trap cleanup EXIT

python3 "$ROOT/tools/deploy_online_stack.py" \
  --project-name "${COLONY_PROJECT_NAME:-colony.io}" \
  "$@"
