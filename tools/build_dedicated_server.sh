#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "Godot executable not found: $GODOT_BIN" >&2
  exit 1
fi
if ! command -v timeout >/dev/null 2>&1; then
  echo "GNU timeout is required" >&2
  exit 1
fi

VERSION="$($GODOT_BIN --version 2>/dev/null | head -n 1)"
if [[ "$VERSION" != 4.6.3* ]]; then
  echo "Godot 4.6.3 is required, found: $VERSION" >&2
  exit 1
fi

run_timed() {
  local label="$1"
  local seconds="$2"
  shift 2
  echo
  echo "===== START: $label (timeout=${seconds}s) ====="
  if timeout --foreground "${seconds}s" "$@"; then
    echo "===== PASS: $label ====="
  else
    local code=$?
    if [[ $code -eq 124 ]]; then
      echo "===== TIMEOUT: $label after ${seconds}s =====" >&2
    else
      echo "===== FAIL: $label (exit=$code) =====" >&2
    fi
    exit "$code"
  fi
}

run_timed "Static online release validation" 180 \
  python3 "$ROOT/tools/validate_online_release.py"

mkdir -p "$ROOT/build/ci-logs"
LOG_DIR="$ROOT/build/ci-logs"
IMPORT_LOG="$LOG_DIR/godot-editor-import.log"

echo
echo "===== START: Godot editor import/parse (timeout=240s) ====="

set +e
timeout --foreground 240s \
  "$GODOT_BIN" --headless --path "$ROOT" --editor --quit \
  2>&1 | tee "$IMPORT_LOG"
IMPORT_CODE=${PIPESTATUS[0]}
set -e

if [[ $IMPORT_CODE -ne 0 ]]; then
  echo "===== FAIL: Godot editor import/parse (exit=$IMPORT_CODE) =====" >&2
  exit "$IMPORT_CODE"
fi

IMPORT_ERROR_PATTERN='SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script'

if grep -Eq "$IMPORT_ERROR_PATTERN" "$IMPORT_LOG"; then
  echo "===== FAIL: Godot import contained script errors =====" >&2
  grep -En "$IMPORT_ERROR_PATTERN" "$IMPORT_LOG" >&2 || true
  exit 1
fi

echo "===== PASS: Godot editor import/parse ====="

TESTS=(
  tests/phase_04_5_1_compile_smoke_test.gd
  tests/online_foundation_regression_test.gd
  tests/online_security_contract_test.gd
  tests/online_transport_regression_test.gd
  tests/online_presentation_parity_regression_test.gd
  tests/online_production_completion_test.gd
  tests/north_world_depth_regression_test.gd
)

for test_path in "${TESTS[@]}"; do
  test_name="$(basename "$test_path" .gd)"
  test_log="$LOG_DIR/${test_name}.log"
  echo
  echo "===== START: Godot test: $test_path (timeout=120s) ====="
  set +e
  timeout --foreground 120s \
    "$GODOT_BIN" --headless --path "$ROOT" --script "res://$test_path" \
    2>&1 | tee "$test_log"
  test_code=${PIPESTATUS[0]}
  set -e
  if [[ $test_code -ne 0 ]]; then
    echo "===== FAIL: Godot test: $test_path (exit=$test_code) =====" >&2
    exit "$test_code"
  fi
  echo "===== PASS: Godot test: $test_path ====="
done

mkdir -p "$ROOT/build/server"
EXPORT_LOG="$LOG_DIR/dedicated-server-export.log"
echo
echo "===== START: Dedicated Server export (timeout=600s) ====="
set +e
timeout --foreground 600s \
  "$GODOT_BIN" --headless --path "$ROOT" \
  --export-release "Dedicated Server" "$ROOT/build/server/colony-dominion-server.x86_64" \
  2>&1 | tee "$EXPORT_LOG"
export_code=${PIPESTATUS[0]}
set -e
if [[ $export_code -ne 0 ]]; then
  echo "===== FAIL: Dedicated Server export (exit=$export_code) =====" >&2
  exit "$export_code"
fi
echo "===== PASS: Dedicated Server export ====="

test -x "$ROOT/build/server/colony-dominion-server.x86_64"
test -s "$ROOT/build/server/colony-dominion-server.pck"
echo "DEDICATED_SERVER_BUILD_OK"
