#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_SUPABASE=0
SKIP_RIVET=0

for argument in "$@"; do
  case "$argument" in
    --skip-supabase) SKIP_SUPABASE=1 ;;
    --skip-rivet) SKIP_RIVET=1 ;;
  esac
done

if (( SKIP_SUPABASE == 1 && SKIP_RIVET == 1 )); then
  echo "Both Supabase and Rivet were skipped; there is nothing to deploy." >&2
  exit 2
fi

require_secret() {
  local variable_name="$1"
  local prompt="$2"
  local purpose="$3"

  if [[ -n "${!variable_name:-}" ]]; then
    return 0
  fi

  if [[ -t 0 ]]; then
    local value=""
    if ! read -rsp "$prompt" value; then
      echo >&2
      echo "Failed to read $variable_name." >&2
      exit 2
    fi
    echo
    if [[ -z "$value" ]]; then
      echo "$variable_name is required for $purpose." >&2
      exit 2
    fi
    printf -v "$variable_name" '%s' "$value"
    export "$variable_name"
    unset value
    return 0
  fi

  echo "$variable_name is required for $purpose and cannot be prompted in non-interactive CI." >&2
  exit 2
}

if (( SKIP_SUPABASE == 0 )); then
  require_secret \
    SUPABASE_ACCESS_TOKEN \
    "Supabase temporary Personal Access Token: " \
    "Supabase Management API access"
fi

if (( SKIP_RIVET == 0 )); then
  require_secret \
    RIVET_CLOUD_TOKEN \
    "Rivet deployment token: " \
    "Rivet deployment"
  require_secret \
    SUPABASE_SECRET_KEY \
    "Supabase backend secret key (never the client key): " \
    "authoritative server writes"
  if [[ -z "${RIVET_ALLOCATOR_URL:-}" ]]; then
    require_secret \
      RIVET_ALLOCATOR_CLOUD_TOKEN \
      "Rivet scoped allocator runtime token: " \
      "direct game-server allocation"
  fi
fi

cleanup() {
  unset SUPABASE_ACCESS_TOKEN RIVET_CLOUD_TOKEN SUPABASE_SECRET_KEY \
    RIVET_ALLOCATOR_CLOUD_TOKEN
}
trap cleanup EXIT

python3 "$ROOT/tools/deploy_online_stack.py" \
  --project-name "${COLONY_PROJECT_NAME:-colony.io}" \
  "$@"
