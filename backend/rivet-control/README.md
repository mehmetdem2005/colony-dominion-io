# Rivet Control Plane — Phase 05.3

Public endpoints:

- `GET /v1/health`
- `GET /v1/health/config`
- `GET /v1/health/ping` (control diagnostics only; never used as player latency)
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

1. `RIVET_ALLOCATOR_URL`: protected external allocator adapter for an approved authoritative game-server host.
2. Legacy direct allocation through `@rivet-gg/api`: retained only for compatibility and source auditing. The current Rivet Compute staging workflow does not enable this path. Do not inject its runtime variables or claim UDP game-server hosting is ready until a current, officially supported Rivet game-server deployment contract is verified.
3. Explicit local development server; disabled in production unless deliberately enabled.

The broad `RIVET_CLOUD_TOKEN` is deployment-only and must not be injected into the running
control plane. Any future allocator integration must use a separate least-privilege runtime credential.

`regionProbe` actors are created once per enabled region and pinned with
`createInRegion`. The EU probe and every EU game actor use Rivet's `fra` region;
the public control actor is pinned there separately. Clients validate the probe
payload identity before displaying latency, so control-plane startup time can no
longer be mislabeled as game ping.

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
npm install --no-audit --no-fund
npm run typecheck
npm run build
npx --yes @rivetkit/cli@latest deploy
```

The repository's staging workflow deploys and verifies the RivetKit control plane on Rivet Compute.
It intentionally reports the authoritative UDP game-server allocator as unavailable until that
separate hosting path is approved and verified.

Protected values must be provisioned through Rivet/CI runtime secret storage, never CLI arguments,
Android configuration or committed files.
