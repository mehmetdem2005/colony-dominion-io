#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NETEM_DEVICE="${NETEM_INTERFACE:-lo}"

run_baseline() {
  echo "=== baseline: no traffic shaping ==="
  REPORT_DIR="$ROOT/build/network-matrix/baseline" \
    NETEM_INTERFACE="" NETEM_DELAY_MS=0 NETEM_JITTER_MS=0 NETEM_LOSS_PERCENT=0 \
    "$ROOT/tools/run_online_soak.sh"
}

run_shaped_case() {
  local name="$1" delay="$2" jitter="$3" loss="$4"
  echo "=== $name: ${delay}ms ±${jitter}ms loss ${loss}% on $NETEM_DEVICE ==="
  REPORT_DIR="$ROOT/build/network-matrix/$name" NETEM_INTERFACE="$NETEM_DEVICE" \
    NETEM_DELAY_MS="$delay" NETEM_JITTER_MS="$jitter" NETEM_LOSS_PERCENT="$loss" \
    "$ROOT/tools/run_online_soak.sh"
}

run_baseline
if [[ "$(id -u)" != "0" ]]; then
  echo "Impaired scenarios require root so tc/netem can shape UDP traffic." >&2
  exit 2
fi
command -v tc >/dev/null 2>&1 || {
  echo "The iproute2 tc command is required for impaired scenarios." >&2
  exit 2
}
ip link show "$NETEM_DEVICE" >/dev/null 2>&1 || {
  echo "NETEM interface does not exist: $NETEM_DEVICE" >&2
  exit 2
}
run_shaped_case europe-mobile 45 8 0.3
run_shaped_case transatlantic 120 20 1
run_shaped_case stressed-mobile 180 45 3
