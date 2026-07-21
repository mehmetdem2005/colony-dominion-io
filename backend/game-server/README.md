# Godot Dedicated Game Server — Phase 05.4

Export the `Dedicated Server` preset first:

```bash
godot --headless --path . --export-release "Dedicated Server"
```

Build the authoritative server image from the Godot project root:

```bash
docker build -f backend/game-server/Dockerfile -t colony-dominion-server:05.4.0 .
```

The container now includes:

- ENet/UDP authoritative transport on `GAME_PORT` (default `7000`).
- Private HTTP `/health`, `/ready`, and `/metrics` endpoints on `CONTROL_PORT` (default `7001`).
- One-time join-ticket consumption through the protected control plane.
- Build, protocol, match, and server identity verification.
- 20 Hz relevance-capped snapshots, authoritative resource state, and 30 Hz player input.
- Sixty-second reconnect reservations and explicit voluntary leave.
- Server-authoritative match-result reporting before graceful shutdown.

The allocator must inject all values documented in `ALLOCATION_CONTRACT.md`. The image intentionally contains no Supabase secret or Rivet deployment token.

Local development may set `DEV_ACCEPT_JOIN_TICKETS=1`; never enable it in a production container.
