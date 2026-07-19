# Rivet Control Plane — Phase 05.3

Public endpoints:

- `GET /v1/health`
- `GET /v1/health/config`
- `GET /v1/health/ping`
- `GET /v1/regions`
- `POST /v1/matchmaking/join`
- `GET /v1/matchmaking/status/:ticket`
- `DELETE /v1/matchmaking/:ticket`

Protected game-server endpoints:

- `POST /v1/internal/sessions/consume`
- `POST /v1/internal/matches/result`

Supabase JWTs are verified against the project's public JWKS endpoint. The queue rejects a
`player_id` that differs from the JWT subject. RivetKit actor state owns queue tickets,
assignment state, hashed one-time join tickets and per-server credential hashes.

## Allocation modes

1. `RIVET_ALLOCATOR_URL`: protected external allocator adapter.
2. Direct Rivet allocation through `@rivet-gg/api`, using `RIVET_ALLOCATOR_CLOUD_TOKEN`, project, environment and build tag.
3. Explicit local development server; disabled in production unless deliberately enabled.

The broad `RIVET_CLOUD_TOKEN` is deployment-only and must not be injected into the running
control plane. Direct allocation uses a separate scoped runtime token.

Each allocation generates a random per-server authentication token. Only its hash is persisted
in actor state; the raw token is injected into that one Godot container. No shared static
`GAME_SERVER_AUTH_TOKEN` is required across all matches.

## Result processing

The dedicated server submits placements and scores. The control plane authenticates the exact
server/match pair, calls the service-role-only Supabase function, and releases matchmaking state.
The SQL function uses an advisory transaction lock and `ratings_processed_at`, so retries cannot
apply MMR twice.

## Validation and deployment

```bash
npm install
npm run typecheck
npm run build
npx rivet-cli@latest deploy
```

Protected values must be provisioned through Rivet/CI runtime secret storage, never CLI arguments,
Android configuration or committed files.
