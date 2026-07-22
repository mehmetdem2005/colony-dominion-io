import { randomBytes, randomUUID } from "node:crypto";
import { createClient } from "rivetkit/client";
import { runtimeRegistry } from "./runtime-registry.js";

const delay = (milliseconds: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, milliseconds));

export async function runStartupCanary(): Promise<void> {
  if (process.env.RIVET_STARTUP_CANARY !== "1") return;
  const port = Number(process.env.RIVET_PORT ?? process.env.PORT ?? 3000);
  const baseUrl = process.env.INTERNAL_BASE_URL ?? `http://127.0.0.1:${port}`;
  const client = createClient<typeof runtimeRegistry>(`${baseUrl}/api/rivet`);
  const matchId = randomUUID();
  const serverId = randomUUID();
  const actorHandle = await client.gameServer.create([`canary-${matchId}`], {
    input: {
      matchId,
      serverId,
      regionId: "canary",
      buildId: process.env.SUPPORTED_BUILD_ID ?? "PHASE-05.5-GOOGLE-BOT-BACKFILL",
      protocolVersion: Number(process.env.PROTOCOL_VERSION ?? 4),
      expectedPlayers: 1,
      maxPlayers: 1,
      humanPlayerCount: 1,
      botCount: 0,
      ranked: true,
      matchSeed: 1,
      serverAuthToken: randomBytes(32).toString("base64url"),
    },
    region: process.env.CONTROL_PROVIDER_REGION?.trim() || "fra",
  });

  try {
    const status = await actorHandle.getStatus();
    if (!status.ready || status.status !== "ready") {
      throw new Error(`Game actor canary was not ready: ${JSON.stringify(status)}`);
    }
    const gatewayUrl = await actorHandle.getGatewayUrl();
    if (!gatewayUrl.startsWith("https://") && !gatewayUrl.startsWith("http://")) {
      throw new Error(`Game actor canary returned invalid gateway URL: ${gatewayUrl}`);
    }
    const websocket = await actorHandle.webSocket("/");
    await delay(250);
    if (websocket.readyState !== WebSocket.OPEN) {
      throw new Error(`Game actor canary WebSocket was not open: ${websocket.readyState}`);
    }
    websocket.close(1000, "canary_complete");
    console.log(JSON.stringify({
      marker: "RIVET_GAME_ACTOR_CANARY_OK",
      match_id: matchId,
      server_id: serverId,
      status: status.status,
      gateway: true,
      websocket_bridge: true,
    }));
  } finally {
    await actorHandle.shutdown("startup_canary_complete").catch(() => undefined);
  }
}
