#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${GAME_SERVER_IMAGE_TAG:-colony-dominion-server:05.3.1}"
ARCHIVE="${RIVET_BUILD_ARCHIVE:-$ROOT/build/server/colony-dominion-server-image.tar}"
CONTEXT_OUTPUT="${RIVET_CONTEXT_OUTPUT:-$ROOT/build/rivet-context.env}"
PUBLISH_LOG="${RIVET_PUBLISH_LOG:-$ROOT/build/diagnostics/rivet-build-publish.log}"

for variable in RIVET_CLOUD_TOKEN RIVET_ENVIRONMENT RIVET_GAME_SERVER_BUILD_TAG; do
  if [[ -z "${!variable:-}" ]]; then
    echo "$variable is required" >&2
    exit 2
  fi
done
command -v docker >/dev/null 2>&1 || { echo "Docker is required" >&2; exit 2; }

if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  IMAGE_TAG="$IMAGE_TAG" "$ROOT/tools/build_game_server_image.sh"
fi
mkdir -p "$(dirname "$ARCHIVE")" "$(dirname "$CONTEXT_OUTPUT")" "$(dirname "$PUBLISH_LOG")"
rm -f "$ARCHIVE" "$CONTEXT_OUTPUT" "$PUBLISH_LOG"
docker save "$IMAGE_TAG" --output "$ARCHIVE"
test -s "$ARCHIVE"

CONTROL="$ROOT/backend/rivet-control"
if [[ -f "$CONTROL/package-lock.json" ]]; then
  npm --prefix "$CONTROL" ci --no-audit --no-fund
else
  npm --prefix "$CONTROL" install --no-audit --no-fund
fi
export RIVET_BUILD_ARCHIVE="$ARCHIVE"
export RIVET_CONTEXT_OUTPUT="$CONTEXT_OUTPUT"

attempt=1
max_attempts=4
while (( attempt <= max_attempts )); do
  : > "$PUBLISH_LOG"
  echo "[Rivet] Publish attempt $attempt/$max_attempts"
  set +e
  npm --prefix "$CONTROL" run publish-build 2>&1 | tee "$PUBLISH_LOG"
  publish_code=${PIPESTATUS[0]}
  set -e

  if [[ $publish_code -eq 0 ]]; then
    test -s "$CONTEXT_OUTPUT"
    rm -f "$ARCHIVE"
    echo "RIVET_GAME_SERVER_BUILD_PUBLISHED"
    exit 0
  fi

  if ! grep -Eq 'Status code: 5[0-9]{2}|RIVET_BUILD_PUBLISH_FAILED: InternalError|RIVET_CONTEXT_HTTP_5[0-9]{2}' "$PUBLISH_LOG"; then
    echo "Rivet publish failed with a non-transient error; retry suppressed." >&2
    exit "$publish_code"
  fi

  if (( attempt == max_attempts )); then
    echo "Rivet publish remained unavailable after $max_attempts attempts." >&2
    echo "Preserve the rayId from $PUBLISH_LOG when contacting Rivet support." >&2
    exit "$publish_code"
  fi

  delay=$((15 * attempt))
  echo "Rivet returned a transient 5xx response; retrying in ${delay}s." >&2
  sleep "$delay"
  attempt=$((attempt + 1))
done
