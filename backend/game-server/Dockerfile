FROM debian:bookworm-slim

ARG TARGETARCH
ARG GODOT_VERSION=4.6.3

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip tini libstdc++6 libgcc-s1 \
        libx11-6 libxcursor1 libxinerama1 libxi6 libxrandr2 \
        libgl1 libfontconfig1 libasound2 libpulse0 libudev1 \
        libwayland-client0 libdbus-1-3 \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) godot_arch="x86_64" ;; \
      arm64) godot_arch="arm64" ;; \
      *) echo "Unsupported container architecture: ${TARGETARCH}" >&2; exit 64 ;; \
    esac; \
    archive="Godot_v${GODOT_VERSION}-stable_linux.${godot_arch}.zip"; \
    url="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/${archive}"; \
    mkdir -p /tmp/godot; \
    curl --fail --location --retry 5 --retry-all-errors "$url" --output /tmp/godot.zip; \
    unzip -q /tmp/godot.zip -d /tmp/godot; \
    binary="$(find /tmp/godot -maxdepth 1 -type f -name 'Godot_v*-stable_linux.*' | head -n 1)"; \
    test -n "$binary"; \
    install -m 0555 "$binary" /usr/local/bin/godot; \
    /usr/local/bin/godot --headless --version; \
    rm -rf /tmp/godot /tmp/godot.zip

WORKDIR /app
COPY build/server/colony-dominion-server.pck /app/colony-dominion-server.pck
COPY backend/game-server/entrypoint.sh /app/entrypoint.sh
RUN chmod 0555 /app/entrypoint.sh \
    && chown -R 10001:10001 /app

EXPOSE 7000/udp
EXPOSE 7001/tcp

ENV GODOT_BIN=/usr/local/bin/godot \
    GAME_PORT=7000 \
    CONTROL_PORT=7001 \
    MAX_PLAYERS=6 \
    EXPECTED_PLAYERS=2 \
    PROTOCOL_VERSION=3 \
    BUILD_ID=PHASE-05.3-ONLINE-PRODUCTION-COMPLETION \
    RANKED_MATCH=1 \
    HOME=/tmp \
    XDG_DATA_HOME=/tmp/.local/share

HEALTHCHECK --interval=10s --timeout=3s --start-period=25s --retries=3 \
    CMD curl -fsS http://127.0.0.1:7001/ready || exit 1

STOPSIGNAL SIGTERM
USER 10001:10001
ENTRYPOINT ["/app/entrypoint.sh"]
