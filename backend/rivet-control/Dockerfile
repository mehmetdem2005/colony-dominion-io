FROM node:24-bookworm-slim AS build
WORKDIR /app/control
COPY backend/rivet-control/package*.json ./
RUN npm install --no-audit --no-fund
COPY backend/rivet-control/tsconfig.json ./
COPY backend/rivet-control/src ./src
RUN npm run typecheck && npm run build

FROM node:24-bookworm-slim AS runtime
ARG GODOT_VERSION=4.6.3
ENV NODE_ENV=production \
    RIVET_PORT=3000 \
    GODOT_BIN=/usr/local/bin/godot \
    GODOT_PCK_PATH=/app/game/colony-dominion-server.pck \
    HOME=/tmp \
    XDG_DATA_HOME=/tmp/.local/share

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip tini libstdc++6 libgcc-s1 \
        libx11-6 libxcursor1 libxinerama1 libxi6 libxrandr2 \
        libgl1 libfontconfig1 libasound2 libpulse0 libudev1 \
        libwayland-client0 libdbus-1-3 \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    archive="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"; \
    url="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/${archive}"; \
    mkdir -p /tmp/godot; \
    curl --fail --location --retry 5 --retry-all-errors "$url" --output /tmp/godot.zip; \
    unzip -q /tmp/godot.zip -d /tmp/godot; \
    binary="$(find /tmp/godot -maxdepth 1 -type f -name 'Godot_v*-stable_linux.*' | head -n 1)"; \
    test -n "$binary"; \
    install -m 0555 "$binary" /usr/local/bin/godot; \
    /usr/local/bin/godot --headless --version; \
    rm -rf /tmp/godot /tmp/godot.zip

WORKDIR /app/control
COPY backend/rivet-control/package*.json ./
RUN npm install --omit=dev --no-audit --no-fund && npm cache clean --force
COPY --from=build /app/control/dist ./dist

WORKDIR /app/game
COPY build/server/colony-dominion-server.pck ./colony-dominion-server.pck
RUN chown -R node:node /app/control /app/game /tmp

USER node
EXPOSE 3000
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "/app/control/dist/server-full-online.js"]
