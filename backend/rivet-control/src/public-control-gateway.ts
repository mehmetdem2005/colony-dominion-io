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
  const actorGatewayUrl = (await actorHandle.getGatewayUrl()).replace(/\/$/, "");
  const publicBaseUrl = `${actorGatewayUrl}/request`;

  if (process.env.NODE_ENV === "production" && !publicBaseUrl.startsWith("https://")) {
    throw new Error(`Public control gateway must use HTTPS in production: ${publicBaseUrl}`);
  }

  let lastError = "gateway probe did not run";
  for (let attempt = 1; attempt <= 20; attempt += 1) {
    try {
      const response = await fetch(`${publicBaseUrl}/v1/health`, {
        headers: { accept: "application/json", "user-agent": "colony-control-bootstrap" },
        signal: AbortSignal.timeout(10_000),
      });
      const payload = (await response.json().catch(() => null)) as { ok?: boolean } | null;
      if (response.ok && payload?.ok === true) {
        console.log(JSON.stringify({
          marker: "RIVET_PUBLIC_CONTROL_GATEWAY_READY",
          actor_key: PUBLIC_CONTROL_ACTOR_KEY,
          public_base_url: publicBaseUrl,
          health_verified: true,
        }));
        return publicBaseUrl;
      }
      lastError = `HTTP ${response.status}: ${JSON.stringify(payload)}`;
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
    await delay(Math.min(500 * attempt, 3_000));
  }

  throw new Error(`Public control gateway did not become ready: ${lastError}`);
}
