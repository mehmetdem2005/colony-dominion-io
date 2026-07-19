# Colony Dominion.io — Live Deployment Steps

Use a **private** GitHub repository and GitHub Environments named `staging` and `production`.
Never paste deployment or backend secrets into the project, Android config, issues, workflow files,
or chat messages.

## Required environment secrets

- `SUPABASE_ACCESS_TOKEN`: temporary Supabase personal access token; revoke after deployment.
- `SUPABASE_SECRET_KEY`: backend-only `sb_secret_...` key.
- `RIVET_CLOUD_TOKEN`: temporary deployment/build publishing token.
- `RIVET_ALLOCATOR_CLOUD_TOKEN`: separate runtime token limited to actor/container allocation.

## Required environment variables

- `SUPABASE_PROJECT_REF`: exact Supabase project reference.
- `COLONY_PROJECT_NAME`: `colony.io`.
- `RIVET_PROJECT`: Rivet project slug.
- `REGIONS_JSON`: optional JSON array. Leave empty for Europe-only staging fallback.

## Order

1. Run **Deploy Online Staging** manually.
2. Download `colony-staging-release` and install the APK on two phones.
3. Verify account creation, legal acceptance, region ping, queue, match, disconnect/reconnect,
   result persistence and MMR idempotency.
4. Configure the GitHub `production` environment with required reviewers.
5. Run **Deploy Online Production**, typing `DEPLOY-PRODUCTION`.
6. Revoke temporary Supabase and Rivet deployment tokens. Keep and rotate only backend/runtime
   secrets in protected environment secret stores.

Optional variables:

- `RIVET_ORG`: only when the project belongs to an organization and the CLI requires it.
- `RIVET_CONTROL_URL`: set only when a control-plane endpoint already exists.

The workflows do not need a package lock. They install exact versions from `package.json`; the
TypeScript version is pinned to the existing stable `5.9.3` release.
