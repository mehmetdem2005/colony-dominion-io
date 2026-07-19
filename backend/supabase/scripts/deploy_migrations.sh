#!/usr/bin/env bash
set -euo pipefail

: "${SUPABASE_PROJECT_REF:?Set SUPABASE_PROJECT_REF}"
: "${SUPABASE_ACCESS_TOKEN:?Set a temporary Supabase personal access token}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPABASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SUPABASE_DIR"

npx supabase@latest link --project-ref "$SUPABASE_PROJECT_REF"
npx supabase@latest db push --dry-run
npx supabase@latest db push
