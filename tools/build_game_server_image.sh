#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${IMAGE_TAG:-colony-dominion-server:05.3}"
GODOT_VERSION="${GODOT_VERSION:-4.6.3}"

if [[ ! -s "$ROOT/build/server/colony-dominion-server.pck" ]]; then
  SKIP_ANDROID_EXPORT=1 "$ROOT/tools/build_release_artifacts.sh"
fi

[[ -s "$ROOT/build/server/colony-dominion-server.pck" ]] || {
  echo "Dedicated-server PCK is missing" >&2
  exit 2
}
command -v docker >/dev/null 2>&1 || { echo "Docker is required" >&2; exit 2; }

docker build --pull \
  --build-arg "GODOT_VERSION=$GODOT_VERSION" \
  -f "$ROOT/backend/game-server/Dockerfile" \
  -t "$IMAGE_TAG" \
  "$ROOT"
docker image inspect "$IMAGE_TAG" --format '{{.Id}} {{.Architecture}}' \
  | tee "$ROOT/build/server-container-image.txt"
echo "Built $IMAGE_TAG"
