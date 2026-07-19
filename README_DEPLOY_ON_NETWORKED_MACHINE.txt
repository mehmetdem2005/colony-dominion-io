COLONY DOMINION.IO — PHASE 05.3 PRODUCTION DEPLOYMENT

Requirements:
- Internet-enabled Linux
- Python 3
- Node.js 22+ and npm
- Docker
- Godot 4.6.3 with Linux and Android export templates
- Fresh temporary Supabase Personal Access Token
- Supabase backend secret key stored only in the deployment/runtime secret store
- Fresh temporary Rivet deployment token
- Separate scoped Rivet allocator runtime token, unless an external allocator URL is used
- Rivet project, environment and uploaded game-server build tag

From the project root:

  export RIVET_PROJECT="YOUR_PROJECT"
  export RIVET_ENVIRONMENT="production"
  export RIVET_GAME_SERVER_BUILD_TAG="colony-server-05-3"
  ./tools/deploy_online_stack.sh --project-name colony.io

The deployment script:
- selects exactly one Supabase project and refuses ambiguous matches;
- applies and verifies all migrations and RLS;
- writes only the client-safe Supabase publishable key to Godot configuration;
- deploys and verifies the Rivet control plane;
- passes protected values only through process environment/runtime secret boundaries;
- verifies health, runtime configuration and the region catalog;
- never writes management, allocator or backend-write tokens into Android files.

Before control-plane deployment, build and publish the exact Godot dedicated-server image:

  ./tools/build_dedicated_server.sh
  ./tools/build_game_server_image.sh
  RIVET_GAME_SERVER_PUBLISH_COMMAND='YOUR APPROVED RIVET PUBLISH COMMAND' \
    ./tools/publish_rivet_game_server.sh

After staging deployment:

  sudo NETEM_INTERFACE=lo DURATION_SECONDS=1800 ./tools/run_network_matrix.sh

Revoke temporary management/deployment tokens after deployment. Keep runtime secrets in the
Rivet/CI secret store and rotate them independently of Android releases.
