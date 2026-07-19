# Phase 05.1 — Online foundation

## Implemented

- New main menu with separate offline and multiplayer flows.
- Offline mode remains independent of Supabase and Rivet.
- Supabase email/password authentication client with JWT session handling.
- Client-side Supabase Data API client for profile, preferences, and legal acceptance records.
- Match-scoped legal gate with separate mandatory documents and optional analytics consent.
- Server-stamped, versioned legal acceptance schema protected by Row Level Security.
- Dynamic Rivet region directory and continuous three-sample latency probes.
- Automatic region selection based on median latency, jitter, packet loss, and availability.
- Manual Europe, North America East/West, South America, Asia, Oceania, and Africa selection.
- Persistent region and ping overlay in menu and gameplay.
- RivetKit matchmaking control-plane project with Supabase JWKS verification, queue actors, build/protocol gates, server allocation contract, and single-use join tickets.
- Godot dedicated-server Dockerfile and Android INTERNET permission.
- Client-safe configuration writer that refuses secret/service-role keys.

## Deliberate boundary

Phase 05.1 stops after a verified server assignment. It does not open a local match and pretend it is multiplayer. Phase 05.3 must add the real ENet client/server transport, authentication handshake, server snapshots, interpolation, prediction, reconciliation, reconnect, and disconnect handling before the online button can enter gameplay.

## Deployment dependencies

The following external values are still required:

- Supabase project URL and publishable key.
- Temporary Supabase CLI access for database migration deployment.
- Rivet project/environment and CLI authentication.
- Rivet game-server container allocation endpoint or final Containers API credentials.
- Final lawyer-reviewed legal documents and production versions replacing `1.0.0-draft`.
