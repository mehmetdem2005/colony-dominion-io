# Rivet-Only Full Online Architecture

## Provider boundary

The production runtime uses Rivet Compute and Rivet Actors only. No Oracle, external Docker allocator, standalone VM, or legacy Rivet Build API is part of the deployment.

## Runtime topology

1. The control plane and RivetKit registry run in one Rivet Compute image.
2. The matchmaker is a durable Rivet actor.
3. Each assigned match creates one keyed `gameServer` Rivet actor.
4. The game actor starts one isolated Godot 4.6.3 headless child process from the validated dedicated-server PCK.
5. Godot binds its WebSocket multiplayer port and HTTP readiness port to loopback only.
6. Rivet's authenticated actor gateway terminates the public WebSocket connection.
7. The game actor forwards binary WebSocket frames between the gateway and the loopback Godot server.
8. Join tickets remain one-time, player-bound, match-bound, server-bound, build-bound, and protocol-bound.
9. Match results are accepted only with the per-match server credential and written through the Supabase service role on the control plane.
10. Match completion destroys the Rivet game actor and terminates the Godot process.

## Production contract

- Build ID: `PHASE-05.5-GOOGLE-BOT-BACKFILL`
- Protocol: `4`
- Client transport: `WebSocketMultiplayerPeer`
- Public endpoint: Rivet actor gateway `wss://.../websocket/`
- Minimum players: `2`
- Maximum players: `10`
- Authoritative colony slots: `10`
- Reconnect reservation: `60 seconds`
- Snapshot cadence: `20 Hz`
- Input cadence: `30 Hz`
- Rivet pool resources: `2 CPU`, `2 GiB RAM`
- Maximum actors per instance: `3`
- Maximum staging scale: `4 instances`

## Failure model

- A Godot child that fails readiness is terminated and never receives a public assignment.
- A child crash closes all proxied client sockets and is retried at most twice.
- Actor destroy or sleep terminates the child with `SIGTERM`, then `SIGKILL` after the grace deadline.
- A failed deployment startup canary terminates the Rivet runtime process so the instance cannot remain falsely healthy.
- Match result writes and join-ticket consumption require the per-match server credential.

## Required evidence before merge

- TypeScript strict typecheck and build pass.
- All GDScript parses, lints, and formatting checks pass.
- Online security, transport, production, and foundation regression tests pass.
- Dedicated-server PCK exports with Godot 4.6.3.
- Full Rivet Compute Docker image builds and contains Godot 4.6.3 plus the PCK.
- Startup canary starts a Godot child, observes readiness, resolves the actor gateway, opens the WebSocket bridge, and destroys the actor.
- Staging deployment reaches Rivet managed-pool `ready` and emits `RIVET_GAME_ACTOR_CANARY_OK`.
