import { createClient } from "rivetkit/client";
import { runtimeRegistry } from "./runtime-registry.js";

const delay = (milliseconds: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, milliseconds));

export const PUBLIC_CONTROL_ACTOR_KEY = "public-control-v1";

export async function ensurePublicControlGateway(): Promise<string> {
  const port = Number(process.env.RIVET_PORT ?? process.env.PORT ?? 3000);
  const internalBaseUrl = process.env.INTERNAL_BASE_URL ?? `http://127.0.0.1:${port}`;
  const client = createClient<typeof runtimeRegistry>(`${internalBaseUrl.replace(/\/$/, "")}/api/rivet`);
  const actorHandle = await client.controlApi.getOrCreate([PUBLIC_CONTROL_ACTOR_KEY]);
  const rawGatewayUrl = await actorHandle.getGatewayUrl();
  const gatewayUrl = new URL(rawGatewayUrl);
  gatewayUrl.hash = "";

  // RivetKit 2.3.4 (Engine - Serverless) hands back actor gateway URLs that may
  // carry a routing query string. Do not reject it: the dedicated game-server
  // allocation path already forwards query-bearing gateway URLs to clients, so
  // the control gateway is treated the same way. The request path is inserted
  // before the query string so the composed public URL stays valid.
  const gatewayQuery = gatewayUrl.search;
  gatewayUrl.search = "";
  gatewayUrl.pathname = `${gatewayUrl.pathname.replace(/\/$/, "")}/request`;
  const publicBaseUrl = `${gatewayUrl.toString().replace(/\/$/, "")}${gatewayQuery}`;

  console.log(JSON.stringify({
    marker: "RIVET_CONTROL_GATEWAY_RESOLVED",
    raw_gateway_url: rawGatewayUrl,
    public_base_url: publicBaseUrl,
    has_query: gatewayQuery.length > 0,
  }));

  if (process.env.NODE_ENV === "production" && gatewayUrl.protocol !== "https:") {
    throw new Error(`Public control gateway must use HTTPS in production: ${gatewayUrl.protocol}`);
  }

  // Do not probe the external gateway during managed-pool startup. The external
  // gateway intentionally waits for the pool to become ready, which would create
  // a readiness cycle. Verify the actor locally here; CI verifies the public HTTPS
  // route only after the managed pool reports ready.
  let lastError = "local actor probe did not run";
  for (let attempt = 1; attempt <= 20; attempt += 1) {
    try {
      const response = await actorHandle.fetch("/v1/health", {
        headers: { accept: "application/json", "user-agent": "colony-control-bootstrap-local" },
      });
      const payload = (await response.json().catch(() => null)) as { ok?: boolean } | null;
      if (response.ok && payload?.ok === true) {
        console.log(JSON.stringify({
          marker: "RIVET_PUBLIC_CONTROL_GATEWAY_READY",
          actor_key: PUBLIC_CONTROL_ACTOR_KEY,
          public_base_url: publicBaseUrl,
          health_verified: true,
          verification_scope: "local_actor",
        }));
        return publicBaseUrl;
      }
      lastError = `HTTP ${response.status}: ${JSON.stringify(payload)}`;
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
    await delay(Math.min(250 * attempt, 2_000));
  }

  throw new Error(`Public control actor did not become ready locally: ${lastError}`);
}
