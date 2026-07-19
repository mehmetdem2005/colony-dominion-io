# Production Online Runbook — Phase 05.3

## Release gates

1. Run `tools/build_release_artifacts.sh` with Godot 4.6.3 and export templates installed.
2. Run `tools/build_game_server_image.sh` and scan the OCI image.
3. Apply all Supabase migrations to staging, then run the schema/RLS verifier.
4. Deploy the Rivet control plane and confirm `/v1/health/config` returns `ready: true`.
5. Register the game-server build tag used by `RIVET_GAME_SERVER_BUILD_TAG`.
6. Run the four-profile network matrix with six clients for at least 30 minutes per profile.
7. Promote the exact image digest and Android artifact checksum to production.

## Rollback

- New allocations use the promoted image; existing matches finish on their original image.
- Keep the previous control-plane deployment and server image digest for one release window.
- A protocol change requires a new build ID and protocol version.
- Database changes in this phase are additive. Roll back traffic before database repair.

## Incident checks

- `/ready`: server composition root and ENet listener are ready.
- `/metrics/prometheus`: players, auth rejection, reconnect, command/snapshot volume and tick debt.
- High auth rejection: verify build/protocol, ticket expiry, server identity and clock.
- High snapshot gaps: inspect CPU tick debt, packet loss, relevance cap and UDP routing.
- Match result failure: preserve/retry server result; never calculate MMR on the client.

## Secrets

`SUPABASE_SECRET_KEY`, the scoped `RIVET_ALLOCATOR_CLOUD_TOKEN`, and per-server `GAME_SERVER_AUTH_TOKEN` values belong only in protected runtime secret stores. `RIVET_CLOUD_TOKEN` is deployment-only and must not be injected into the running service.


## Legal release gate

- Replace template legal documents only after Turkish KVKK/GDPR counsel review.
- Keep mandatory terms/community acceptance separate from optional analytics consent.
- Increment document versions and hashes whenever wording changes.
- Verify account deletion, data export and consent withdrawal procedures before store release.
