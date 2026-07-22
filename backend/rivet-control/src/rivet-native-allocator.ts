import { randomBytes, randomUUID } from "node:crypto";
import type { Client } from "rivetkit/client";
import type { GameServerActorInput } from "./game-server-actor.js";
import type { runtimeRegistry } from "./runtime-registry.js";
import type { QueueEntry, RegionDefinition, ServerAssignment } from "./types.js";

export type AllocationResult = {
  assignment: Omit<ServerAssignment, "joinTicket">;
  joinTickets: Record<string, string>;
  serverAuthToken: string;
};

type RuntimeActorClient = Client<typeof runtimeRegistry>;
type GameServerCreateOptions = Parameters<
  RuntimeActorClient["gameServer"]["create"]
>[1];

const ASSIGNMENT_TTL_MS = 120_000;
const MAX_PLAYERS = 10;

export async function allocateRivetGameServer(
  client: RuntimeActorClient,
  region: RegionDefinition,
  players: QueueEntry[],
  targetPlayers: number = MAX_PLAYERS,
): Promise<AllocationResult> {
  if (
    !Number.isInteger(targetPlayers) ||
    targetPlayers < 1 ||
    targetPlayers > MAX_PLAYERS
  ) {
    throw new Error(`Target player count must be between 1 and ${MAX_PLAYERS}`);
  }
  if (players.length === 0 || players.length > targetPlayers) {
    throw new Error(`Rivet game actor requires between 1 and ${MAX_PLAYERS} players`);
  }
  const buildId = players[0]?.buildId ?? "";
  const protocolVersion = players[0]?.protocolVersion ?? 0;
  if (!buildId || !Number.isInteger(protocolVersion) || protocolVersion <= 0) {
    throw new Error("Allocation candidates have invalid build metadata");
  }
  for (const player of players) {
    if (player.buildId !== buildId || player.protocolVersion !== protocolVersion) {
      throw new Error(
        "Allocation candidates do not share the same build and protocol version",
      );
    }
  }

  const matchId = randomUUID();
  const serverId = randomUUID();
  const serverAuthToken = randomBytes(32).toString("base64url");
  const matchSeed = Math.max(
    1,
    randomBytes(4).readUInt32BE(0) & 0x7fffffff,
  );
  const joinTickets = Object.fromEntries(
    players.map((entry) => [
      entry.queueTicketId,
      randomBytes(32).toString("base64url"),
    ]),
  );

  const input: GameServerActorInput = {
    matchId,
    serverId,
    regionId: region.id,
    buildId,
    protocolVersion,
    expectedPlayers: players.length,
    maxPlayers: targetPlayers,
    humanPlayerCount: players.length,
    botCount: Math.max(0, targetPlayers - players.length),
    ranked: players.length === targetPlayers,
    matchSeed,
    serverAuthToken,
  };
  const options: GameServerCreateOptions = { input };
  if (region.providerRegion) {
    // Rivet's create() API uses `region`; `createInRegion` belongs to
    // getOrCreate(). Using the latter silently let game actors land outside FRA.
    options.region = region.providerRegion;
  }
  const handle = await client.gameServer.create([matchId], options);
  const status = await handle.getStatus();
  if (!status.ready || status.status !== "ready") {
    throw new Error(
      `Rivet game actor did not become ready: ${status.lastError ?? status.status}`,
    );
  }

  const gatewayUrl = await handle.getGatewayUrl();
  const websocketUrl = toWebSocketGatewayUrl(gatewayUrl);
  const parsed = new URL(websocketUrl);
  const port = parsed.port
    ? Number(parsed.port)
    : parsed.protocol === "wss:"
      ? 443
      : 80;
  if (
    !parsed.hostname ||
    !Number.isInteger(port) ||
    port <= 0 ||
    port > 65_535
  ) {
    throw new Error("Rivet gateway returned an invalid WebSocket endpoint");
  }

  return {
    assignment: {
      matchId,
      serverId,
      transport: "websocket",
      websocketUrl,
      host: parsed.hostname,
      port,
      regionId: region.id,
      regionName: region.displayName,
      regionShortName: region.shortName,
      expiresAt: Date.now() + ASSIGNMENT_TTL_MS,
      protocolVersion,
      humanPlayers: players.length,
      botPlayers: Math.max(0, targetPlayers - players.length),
      ranked: players.length === targetPlayers,
    },
    joinTickets,
    serverAuthToken,
  };
}

function toWebSocketGatewayUrl(gatewayUrl: string): string {
  const url = new URL(gatewayUrl);
  if (url.protocol === "https:") url.protocol = "wss:";
  else if (url.protocol === "http:") url.protocol = "ws:";
  else throw new Error(`Unsupported Rivet gateway protocol: ${url.protocol}`);
  url.pathname = `${url.pathname.replace(/\/$/, "")}/websocket/`;
  return url.toString();
}
