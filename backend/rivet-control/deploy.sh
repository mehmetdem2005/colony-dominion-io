#!/usr/bin/env bash
set -euo pipefail

npm install --no-audit --no-fund
npm run typecheck
npm run build
exec npx --yes @rivetkit/cli@latest deploy "$@"
