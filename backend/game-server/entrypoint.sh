#!/usr/bin/env sh
set -eu

required="MATCH_ID SERVER_ID REGION_ID BUILD_ID PROTOCOL_VERSION CONTROL_BASE_URL GAME_SERVER_AUTH_TOKEN"
if [ "${ALLOW_INCOMPLETE_SERVER_ENV:-0}" != "1" ]; then
  for name in $required; do
    eval "value=\${$name:-}"
    if [ -z "$value" ]; then
      echo "[entrypoint] required environment is missing: $name" >&2
      exit 64
    fi
  done
fi

GAME_PORT="${GAME_PORT:-7000}"
CONTROL_PORT="${CONTROL_PORT:-7001}"
MAX_PLAYERS="${MAX_PLAYERS:-10}"
EXPECTED_PLAYERS="${EXPECTED_PLAYERS:-1}"
HUMAN_PLAYER_COUNT="${HUMAN_PLAYER_COUNT:-$EXPECTED_PLAYERS}"
BOT_COUNT="${BOT_COUNT:-$((MAX_PLAYERS - HUMAN_PLAYER_COUNT))}"
RANKED_MATCH="${RANKED_MATCH:-0}"

case "$GAME_PORT" in *[!0-9]*|'') echo "invalid GAME_PORT" >&2; exit 64;; esac
case "$CONTROL_PORT" in *[!0-9]*|'') echo "invalid CONTROL_PORT" >&2; exit 64;; esac
case "$MAX_PLAYERS" in *[!0-9]*|'') echo "invalid MAX_PLAYERS" >&2; exit 64;; esac
case "$EXPECTED_PLAYERS" in *[!0-9]*|'') echo "invalid EXPECTED_PLAYERS" >&2; exit 64;; esac
case "$HUMAN_PLAYER_COUNT" in *[!0-9]*|'') echo "invalid HUMAN_PLAYER_COUNT" >&2; exit 64;; esac
case "$BOT_COUNT" in *[!0-9]*|'') echo "invalid BOT_COUNT" >&2; exit 64;; esac
case "$RANKED_MATCH" in 0|1) : ;; *) echo "invalid RANKED_MATCH" >&2; exit 64;; esac

if [ "$MAX_PLAYERS" -lt 1 ] || [ "$MAX_PLAYERS" -gt 10 ]; then
  echo "MAX_PLAYERS must be between 1 and 10" >&2
  exit 64
fi
if [ "$EXPECTED_PLAYERS" -lt 1 ] || [ "$EXPECTED_PLAYERS" -gt "$MAX_PLAYERS" ]; then
  echo "EXPECTED_PLAYERS must be between 1 and MAX_PLAYERS" >&2
  exit 64
fi
if [ "$HUMAN_PLAYER_COUNT" -lt "$EXPECTED_PLAYERS" ] || [ "$HUMAN_PLAYER_COUNT" -gt "$MAX_PLAYERS" ]; then
  echo "HUMAN_PLAYER_COUNT must be between EXPECTED_PLAYERS and MAX_PLAYERS" >&2
  exit 64
fi
if [ $((HUMAN_PLAYER_COUNT + BOT_COUNT)) -ne "$MAX_PLAYERS" ]; then
  echo "HUMAN_PLAYER_COUNT + BOT_COUNT must equal MAX_PLAYERS" >&2
  exit 64
fi
if [ "$RANKED_MATCH" = "1" ] && [ "$BOT_COUNT" -gt 0 ]; then
  echo "bot-backfilled matches cannot be ranked" >&2
  exit 64
fi

export GAME_PORT CONTROL_PORT MAX_PLAYERS EXPECTED_PLAYERS HUMAN_PLAYER_COUNT BOT_COUNT RANKED_MATCH

exec /usr/bin/tini -- /app/colony-dominion-server.x86_64 --headless --server "$@"
