FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libstdc++6 curl tini \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY build/server/colony-dominion-server.x86_64 /app/colony-dominion-server.x86_64
COPY build/server/colony-dominion-server.pck /app/colony-dominion-server.pck
COPY backend/game-server/entrypoint.sh /app/entrypoint.sh
RUN chmod 0555 /app/colony-dominion-server.x86_64 /app/entrypoint.sh \
    && chown -R 10001:10001 /app

EXPOSE 7000/udp
EXPOSE 7001/tcp

ENV GAME_PORT=7000 \
    CONTROL_PORT=7001 \
    MAX_PLAYERS=10 \
    EXPECTED_PLAYERS=2 \
    PROTOCOL_VERSION=4 \
    BUILD_ID=PHASE-05.4-RIVET-FULL-ONLINE \
    RANKED_MATCH=1

HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:7001/ready || exit 1

STOPSIGNAL SIGTERM
USER 10001:10001
ENTRYPOINT ["/app/entrypoint.sh"]
