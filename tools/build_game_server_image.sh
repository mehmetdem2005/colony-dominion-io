#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${IMAGE_TAG:-colony-dominion-server:05.3}"
[ -x "$ROOT/build/server/colony-dominion-server.x86_64" ] || {
  SKIP_ANDROID_EXPORT=1 "$ROOT/tools/build_release_artifacts.sh"
}
command -v docker >/dev/null 2>&1 || { echo "Docker is required" >&2; exit 2; }
docker build --pull -f "$ROOT/backend/game-server/Dockerfile" -t "$IMAGE_TAG" "$ROOT"
docker image inspect "$IMAGE_TAG" --format '{{.Id}}' | tee "$ROOT/build/server-container-image.txt"
echo "Built $IMAGE_TAG"
