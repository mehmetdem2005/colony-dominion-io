#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
PLAYERS="${PLAYERS:-6}"
DURATION_SECONDS="${DURATION_SECONDS:-180}"
GAME_PORT="${GAME_PORT:-17000}"
CONTROL_PORT="${CONTROL_PORT:-17001}"
REPORT_DIR="${REPORT_DIR:-$ROOT/build/soak/$(date -u +%Y%m%dT%H%M%SZ)}"
MATCH_ID="${MATCH_ID:-$(python3 -c 'import uuid; print(uuid.uuid4())')}"
SERVER_ID="${SERVER_ID:-$(python3 -c 'import uuid; print(uuid.uuid4())')}"
BUILD_ID="PHASE-05.3-ONLINE-PRODUCTION-COMPLETION"
mkdir -p "$REPORT_DIR"
command -v "$GODOT_BIN" >/dev/null 2>&1 || { echo "Godot binary not found" >&2; exit 2; }

cleanup() {
  if [ -n "${SERVER_PID:-}" ]; then kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; fi
  if [ -n "${NETEM_INTERFACE:-}" ] && command -v tc >/dev/null 2>&1 && [ "$(id -u)" = 0 ]; then
    tc qdisc del dev "$NETEM_INTERFACE" root 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if [ -n "${NETEM_INTERFACE:-}" ] && command -v tc >/dev/null 2>&1 && [ "$(id -u)" = 0 ]; then
  tc qdisc replace dev "$NETEM_INTERFACE" root netem \
    delay "${NETEM_DELAY_MS:-0}ms" "${NETEM_JITTER_MS:-0}ms" \
    loss "${NETEM_LOSS_PERCENT:-0}%"
fi

MATCH_ID="$MATCH_ID" SERVER_ID="$SERVER_ID" REGION_ID="local-soak" \
BUILD_ID="$BUILD_ID" PROTOCOL_VERSION=3 GAME_PORT="$GAME_PORT" CONTROL_PORT="$CONTROL_PORT" \
MAX_PLAYERS=6 EXPECTED_PLAYERS="$PLAYERS" DEV_ACCEPT_JOIN_TICKETS=1 RANKED_MATCH=0 \
ALLOW_INCOMPLETE_SERVER_ENV=1 \
"$GODOT_BIN" --headless --path "$ROOT" -- --server >"$REPORT_DIR/server.log" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:$CONTROL_PORT/health" >/dev/null 2>&1; then break; fi
  sleep 0.25
  kill -0 "$SERVER_PID" 2>/dev/null || { cat "$REPORT_DIR/server.log"; exit 1; }
done
curl -fsS "http://127.0.0.1:$CONTROL_PORT/health" > "$REPORT_DIR/server-health.json"

pids=()
for i in $(seq 1 "$PLAYERS"); do
  PLAYER_ID=$(python3 -c 'import uuid; print(uuid.uuid4())')
  "$GODOT_BIN" --headless --path "$ROOT" -- \
    --soak-client \
    --host=127.0.0.1 --port="$GAME_PORT" \
    --match-id="$MATCH_ID" --server-id="$SERVER_ID" \
    --player-id="$PLAYER_ID" --name="Bot$i" --seed="$i" \
    --duration="$DURATION_SECONDS" --report="$REPORT_DIR/bot-$i.json" \
    >"$REPORT_DIR/bot-$i.log" 2>&1 &
  pids+=("$!")
done

status=0
for pid in "${pids[@]}"; do wait "$pid" || status=1; done
curl -fsS "http://127.0.0.1:$CONTROL_PORT/metrics" > "$REPORT_DIR/server-metrics.json" || true
python3 "$ROOT/tools/analyze_soak_reports.py" "$REPORT_DIR" | tee "$REPORT_DIR/summary.json"
exit "$status"
