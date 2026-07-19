# Colony Dominion Online Backend — Phase 05.3

- `supabase/`: Auth-adjacent profile/legal data, season/MMR schema, RLS, match history and idempotent authoritative result processing.
- `rivet-control/`: RivetKit matchmaking actor, Supabase JWT validation, region discovery, one-time session tickets, direct/external container allocation and authoritative result ingestion.
- `game-server/`: Godot 4.6.3 headless authoritative ENet server container boundary.
- `observability/`: Prometheus alert rules for availability, authentication, reconnect, tick debt and match-result failures.

## Secret boundary

The Android client may contain only:

- Supabase project URL
- Supabase publishable key
- Public Rivet control-plane URL
- Public region probe URLs

The following stay only in protected deployment/runtime secret stores:

- Supabase management Personal Access Token
- Supabase backend secret key
- Rivet deployment token
- Scoped Rivet allocator runtime token
- Per-server game-server authentication token
- Database passwords and private signing keys

## Delivered production flow

Supabase login and legal acceptance → region probes → RivetKit queue → Rivet container allocation → one-time join-ticket consumption → Godot ENet authoritative match → reconnect reservation → authoritative match result → idempotent season/MMR update.

Actual account deployment, image publication and cross-region load execution require a networked build host with fresh credentials and Godot/Docker installed.
