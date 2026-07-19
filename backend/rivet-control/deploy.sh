#!/usr/bin/env bash
set -euo pipefail

npm install --no-audit --no-fund
npm run typecheck
npx --yes rivet-cli@latest deploy
