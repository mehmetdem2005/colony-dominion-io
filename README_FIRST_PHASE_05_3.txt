PHASE 05.3 — OPEN THIS PROJECT

1. Extract the complete folder without merging it into an older phase.
2. Import this exact file in Godot 4.6.3:
   colony-dominion-io-phase-05-3-online-production-completion/project.godot
3. Confirm the Output panel contains:
   [Colony Dominion] Build: PHASE-05.3-ONLINE-PRODUCTION-COMPLETION
4. Offline play works without any backend configuration.
5. Online play becomes available after config/backend_config.json contains the public Supabase URL, client-safe publishable key, and public Rivet control URL.

Never place Supabase PAT, sb_secret/service_role, Rivet deployment token, or a game-server credential inside the Godot project.
