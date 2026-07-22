# Colony Dominion.io — Rivet OSS self-host (direct low-latency game servers)

## Why this exists

The game currently runs on Rivet's **managed serverless actors** (RivetKit 2.3.4 →
`api.rivet.dev`). That product reaches actors **only through the Guard gateway**
(`getGatewayUrl()`); there is no direct/host port. Every packet is tunnelled, which
is why EU shows ~500 ms. This is a platform limit of the serverless product, not a
config mistake.

Rivet's **direct connection** (`network_mode: host`, real public UDP port, low
ping) is available on **Rivet Open Source (self-hosted)** and Enterprise only. We
are taking the self-host path.

## Target architecture

```
Player (Godot client, ENet/UDP)
        │  direct UDP to  <server-public-ip>:<host-port>   (~30–60 ms in-region)
        ▼
Self-hosted Rivet OSS engine  (Frankfurt VPS)
        │  starts an actor with network_mode: host
        ▼
Godot dedicated server (headless, containerised) bound to 0.0.0.0:<port>

Supabase (auth + DB)  — unchanged, stays managed.
Matchmaking control  — Rivet actor/HTTP, returns the DIRECT ip:port to the client.
```

The client is already built for this: `game_transport.connect_to_assignment()` →
`ENetMultiplayerPeer.create_client(host, port)`. We only change what `host`/`port`
the allocator returns (a direct public address instead of a gateway URL).

## What you (the owner) need to provision

1. **A VPS in Frankfurt** (EU-central), Linux (Ubuntu 22.04/24.04), public IPv4.
   - Start: **2 vCPU / 4 GB RAM / 40 GB disk** is plenty for testing + first players.
   - Suggested non-Oracle providers: **Hetzner** (`CX22`, ~€4–5/mo, Falkenstein/Nürnberg = Germany), Netcup, Contabo, Scaleway, or Vultr/DigitalOcean Frankfurt.
   - Open firewall ports: `22` (SSH), `6420`/`8080` (Rivet engine + dashboard, can stay private), and a **UDP range for game servers** (e.g. `20000–20100/udp`).
2. **Give the deploy access** — one of:
   - SSH access (a user + key) to that VPS, or
   - You run the provided `setup.sh` yourself and paste back the outputs.

Global later: replicate the same VPS in more regions (e.g. US-East, Asia) and let
matchmaking pick the closest — but **one Frankfurt node first**, prove the latency,
then scale.

## Deployment steps (once the server exists)

1. Install Docker + compose on the VPS.
2. Bring up Rivet OSS engine (single node, file-system/RocksDB backend) via
   `docker-compose.yml` in this folder. Ref: https://rivet.dev/docs/self-hosting/docker-compose/
3. Build + push the **Godot dedicated-server container** (from the existing
   "Dedicated Server" export preset) to the node.
4. Register the game-server actor build with **`network_mode: host`** and a UDP
   port so Rivet hands out a direct `public-ip:port`.
5. Point `backend/rivet-control` (matchmaker) at the self-hosted engine
   (`RIVET_ENDPOINT=http://namespace:token@<vps-ip>:6420`) and change the
   allocator to return the direct address.
6. Update `config/backend_config.json` on the client to the self-hosted control
   endpoint.
7. You install the APK and test real ping in-region.

## Status

- [ ] VPS provisioned + access shared  ← **blocked on owner**
- [ ] Rivet OSS engine running on the VPS
- [ ] Godot dedicated-server container built + pushed
- [ ] Game-server actor registered with host networking (direct UDP port)
- [ ] Matchmaker repointed to self-hosted engine + direct-address allocator
- [ ] Client config repointed
- [ ] On-device latency verified

## Honest notes

- Self-hosting Rivet is real DevOps: you run and pay for the VPS(es). One small
  Frankfurt node is cheap (~€5/mo) and gives real low ping in-region.
- Truly global low ping needs a node per region; we start with one and scale.
- Supabase (auth/DB) and the native Google sign-in work stay exactly as they are.
