# Phase 05.1.1 — Secure Deployment Bootstrap

This phase adds an environment-only deployment tool for the existing Phase 05.1 online foundation.

## Automated workflow

1. Lists Supabase projects through the Management API.
2. Selects the unique project matching `colony.io`, or the explicit `SUPABASE_PROJECT_REF`.
3. Retrieves only a publishable/legacy anon client key. Secret and service-role keys are rejected.
4. Applies the ordered SQL migrations and verifies RLS on every exposed online table.
5. Type-checks/builds and deploys the Rivet control plane with `@rivetkit/cli`.
6. Health-checks the public control endpoint and region catalog.
7. Writes only public client configuration and a secret-free deployment report.

## Run

```bash
cd colony-dominion-io-phase-05-1-1-deployment-bootstrap
./tools/deploy_online_stack.sh --project-name colony.io
```

Tokens are read from hidden prompts or environment variables, passed only to HTTPS/CLI processes, scrubbed on shell exit, and never persisted by this project.

## Important boundary

This phase deploys authentication/database schema and the matchmaking control plane. A protected `RIVET_ALLOCATOR_URL` is still required for real game-server assignment. Native Godot ENet transport, join-ticket verification inside the headless game server, snapshots, prediction/reconciliation, and reconnect are Phase 05.3.
