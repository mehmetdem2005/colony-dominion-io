# Phase 05.3 — Online Production Completion

Build: `PHASE-05.3-ONLINE-PRODUCTION-COMPLETION`  
Protocol: `3`  
Maximum players: `6`

## Completed

- Rivet direct/external dedicated-container allocation boundary.
- Per-player queue ownership and one active queue ticket per account.
- Hashed, expiring, atomic one-time join tickets.
- Per-server authentication credentials and server identity verification.
- Godot ENet server-authoritative input, snapshots, interpolation and reconciliation.
- Persistent encrypted reconnect metadata with 60-second server reservations.
- Voluntary leave separated from transient disconnect.
- Authoritative match-result delivery with retry and controlled server shutdown.
- Supabase season, MMR, rating history, leaderboard and player summary RPCs.
- Advisory-lock and timestamp based duplicate-result protection.
- Linux headless export, non-root Docker image and health checks.
- Six-client soak bot, real `tc/netem` network matrix and report analyzer.
- Prometheus metrics, alert rules and production runbook.
- Safe deployment bootstrap with separate deployment and allocator token scopes.

## External release gates

The source package cannot itself perform account-specific cloud provisioning. A network-enabled
Linux build machine must run the supplied scripts with fresh credentials, Godot 4.6.3 export
templates and Docker. Legal templates require qualified legal review before store publication.
