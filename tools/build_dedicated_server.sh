#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "Godot executable not found: $GODOT_BIN" >&2
  exit 1
fi
VERSION="$($GODOT_BIN --version 2>/dev/null | head -n 1)"
if [[ "$VERSION" != 4.6.3* ]]; then
  echo "Godot 4.6.3 is required, found: $VERSION" >&2
  exit 1
fi

python3 "$ROOT/tools/validate_online_release.py"
"$GODOT_BIN" --headless --path "$ROOT" --editor --quit

TESTS=(
  tests/phase_04_5_1_compile_smoke_test.gd
  tests/online_foundation_regression_test.gd
  tests/online_security_contract_test.gd
  tests/online_transport_regression_test.gd
  tests/online_production_completion_test.gd
  tests/north_world_depth_regression_test.gd
)
for test_path in "${TESTS[@]}"; do
  "$GODOT_BIN" --headless --path "$ROOT" --script "res://$test_path"
done

mkdir -p "$ROOT/build/server"
"$GODOT_BIN" --headless --path "$ROOT" \
  --export-release "Dedicated Server" "$ROOT/build/server/colony-dominion-server.x86_64"

test -x "$ROOT/build/server/colony-dominion-server.x86_64"
test -s "$ROOT/build/server/colony-dominion-server.pck"
echo "DEDICATED_SERVER_BUILD_OK"
