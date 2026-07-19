#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${GAME_SERVER_IMAGE_TAG:-colony-dominion-server:05.3.1}"
ARCHIVE="${RIVET_BUILD_ARCHIVE:-$ROOT/build/server/colony-dominion-server-image.tar}"

for variable in RIVET_CLOUD_TOKEN RIVET_PROJECT RIVET_ENVIRONMENT RIVET_GAME_SERVER_BUILD_TAG; do
  if [[ -z "${!variable:-}" ]]; then
    echo "$variable is required" >&2
    exit 2
  fi
done
command -v docker >/dev/null 2>&1 || { echo "Docker is required" >&2; exit 2; }

if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  IMAGE_TAG="$IMAGE_TAG" "$ROOT/tools/build_game_server_image.sh"
fi
mkdir -p "$(dirname "$ARCHIVE")"
rm -f "$ARCHIVE"
docker save "$IMAGE_TAG" --output "$ARCHIVE"
test -s "$ARCHIVE"

CONTROL="$ROOT/backend/rivet-control"
if [[ -f "$CONTROL/package-lock.json" ]]; then
  npm --prefix "$CONTROL" ci --no-audit --no-fund
else
  npm --prefix "$CONTROL" install --no-audit --no-fund
fi
export RIVET_BUILD_ARCHIVE="$ARCHIVE"
npm --prefix "$CONTROL" run publish-build
rm -f "$ARCHIVE"
echo "RIVET_GAME_SERVER_BUILD_PUBLISHED"
