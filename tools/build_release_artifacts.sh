#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
BUILD_DIR="$ROOT/build"
REPORT_DIR="$BUILD_DIR/reports"
mkdir -p "$BUILD_DIR/server" "$REPORT_DIR"

command -v "$GODOT_BIN" >/dev/null 2>&1 || { echo "Godot binary not found: $GODOT_BIN" >&2; exit 2; }
"$GODOT_BIN" --version | tee "$REPORT_DIR/godot-version.txt"
"$GODOT_BIN" --headless --path "$ROOT" --editor --quit 2>&1 | tee "$REPORT_DIR/import-and-parse.log"

for test in \
  tests/phase_04_5_1_compile_smoke_test.gd \
  tests/architecture_boundaries_test.gd \
  tests/online_foundation_regression_test.gd \
  tests/online_security_contract_test.gd \
  tests/online_transport_regression_test.gd \
  tests/online_production_completion_test.gd; do
  [ -f "$ROOT/$test" ] || continue
  "$GODOT_BIN" --headless --path "$ROOT" --script "res://$test" 2>&1 | tee "$REPORT_DIR/$(basename "$test" .gd).log"
done

"$GODOT_BIN" --headless --path "$ROOT" --export-release "Dedicated Server" 2>&1 | tee "$REPORT_DIR/export-server.log"
test -x "$BUILD_DIR/server/colony-dominion-server.x86_64"
test -s "$BUILD_DIR/server/colony-dominion-server.pck"

if [ "${SKIP_ANDROID_EXPORT:-0}" != "1" ]; then
  "$GODOT_BIN" --headless --path "$ROOT" --export-release "Android" 2>&1 | tee "$REPORT_DIR/export-android.log"
  test -s "$BUILD_DIR/colony-dominion-io.apk"
fi

(
  cd "$BUILD_DIR"
  find . -type f ! -name SHA256SUMS.txt -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS.txt
)
echo "Release artifacts built under $BUILD_DIR"
