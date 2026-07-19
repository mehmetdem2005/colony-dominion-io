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

case "${GAME_PORT:-7000}" in *[!0-9]*|'') echo "invalid GAME_PORT" >&2; exit 64;; esac
case "${CONTROL_PORT:-7001}" in *[!0-9]*|'') echo "invalid CONTROL_PORT" >&2; exit 64;; esac
case "${MAX_PLAYERS:-6}" in *[!0-9]*|'') echo "invalid MAX_PLAYERS" >&2; exit 64;; esac
case "${EXPECTED_PLAYERS:-2}" in *[!0-9]*|'') echo "invalid EXPECTED_PLAYERS" >&2; exit 64;; esac

exec /usr/bin/tini -- /app/colony-dominion-server.x86_64 --headless --server "$@"
