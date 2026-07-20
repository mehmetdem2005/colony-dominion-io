# Rivet Build API Support Report

## Summary

A validated Godot 4.6.3 dedicated-server Docker image cannot be prepared through the legacy Rivet Cloud Build API. Project and namespace resolution succeeds, but `builds.prepare` returns HTTP 500 consistently.

## Environment

- Rivet project name_id: `colony-io-5iy`
- Rivet project id: `d40ffb96-aec1-47fc-b58c-3e1fe16af476`
- Namespace name_id: `staging`
- Namespace id: `ddbcfb06-1a8d-4906-999d-ccbf7c4d73ec`
- Node.js: 22 on GitHub Actions Ubuntu 24.04
- SDK: `@rivet-gg/api` 25.5.3
- Operation: `client.builds.prepare`
- Build kind: `docker_image`
- Compression: `none`

## Validation completed before upload

- Godot import and parse: pass
- Six Godot regression tests: pass
- Rivet control-plane TypeScript typecheck: pass
- Linux dedicated-server export: pass
- Docker image build: pass
- Token project and namespace resolution: pass

## Persistent failures

The API returned `InternalError`, HTTP 500, on four backoff-separated attempts:

1. `6e663d90-e9b5-421c-88c5-c9698258e0f2`
2. `d3c5fb19-adbd-4773-b556-4b627d1c75c2`
3. `1132e763-0079-4cbf-b897-1f36b82ac5f7`
4. `bd2f58e4-ca54-4c8b-b6fb-72a6376b1396`

An earlier identical failure returned:

- `254cad1a-9688-4c97-895e-4813740b434e`

## Request

Please confirm whether the legacy Cloud Build API used by `@rivet-gg/api` 25.5.3 is still supported for publishing dynamically allocated Docker game servers. If supported, inspect the ray IDs above. If it has been replaced, provide the supported API or CLI path for uploading a standalone Godot dedicated-server image that requires UDP game traffic and an HTTP health/control port.

No authentication token or secret is included in this report.
