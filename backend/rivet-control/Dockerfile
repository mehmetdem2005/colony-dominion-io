FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --no-audit --no-fund
COPY tsconfig.json ./
COPY src ./src
RUN npm run typecheck && npm run build

FROM node:22-alpine AS runtime
ENV NODE_ENV=production \
    RIVET_PORT=3000
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force
COPY --from=build /app/dist ./dist
USER node
EXPOSE 3000
CMD ["sh", "-ec", "if [ \"${RIVET_RUNTIME_MODE:-http}\" = runner ]; then exec node dist/self-hosted.js; else exec node dist/server.js; fi"]
