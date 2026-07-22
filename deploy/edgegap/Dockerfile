# Colony Dominion.io — Godot headless dedicated game server image.
#
# Edgegap runs this container on the edge node nearest the matched players and
# maps the internal UDP port to a public ip:port. The Godot client then connects
# DIRECTLY over ENet/UDP (game_transport.connect_to_assignment), so there is no
# gateway hop — real low latency.
#
# CI exports the "Dedicated Server" preset into build/server/ (binary + .pck)
# before this image is built.
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libgcc-s1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY build/server/ /app/
RUN chmod +x /app/colony-dominion-server.x86_64

# Internal port the Godot server binds; Edgegap maps it to a public port and
# reports the external ip:port back to the matchmaker. The match env
# (MATCH_ID, SERVER_ID, BUILD_ID, MAX_PLAYERS, EXPECTED_PLAYERS,
# NETWORK_TRANSPORT, ...) is injected by the matchmaker at deploy time.
ENV GAME_PORT=20000
EXPOSE 20000/udp

# --headless makes boot.gd take the dedicated-server path
# (DisplayServer.get_name() == "headless").
ENTRYPOINT ["/app/colony-dominion-server.x86_64", "--headless"]
