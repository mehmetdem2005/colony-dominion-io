#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${GAME_SERVER_IMAGE_TAG:-colony-dominion-server:05.3.0}"

"$ROOT/tools/build_dedicated_server.sh"
docker build -f "$ROOT/backend/game-server/Dockerfile" -t "$IMAGE_TAG" "$ROOT"
docker image inspect "$IMAGE_TAG" >/dev/null
printf 'ONLINE_RELEASE_IMAGE_READY=%s\n' "$IMAGE_TAG"
