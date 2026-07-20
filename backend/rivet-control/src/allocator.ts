import { randomBytes, randomUUID } from "node:crypto";
import type { QueueEntry, RegionDefinition, ServerAssignment } from "./types.js";

export type AllocationResult = {
  assignment: Omit<ServerAssignment, "joinTicket">;
  joinTickets: Record<string, string>;
  serverAuthToken: string;
};

type ActorPort = { host?: string; port?: number; url?: string; hostname?: string };
type RivetActorResponse = {
  id?: string;
  actorId?: string;
  network?: { ports?: Record<string, ActorPort> };
};

export async function allocateGameServer(
  region: RegionDefinition,
  players: QueueEntry[],
): Promise<AllocationResult> {
  if (players.length === 0) throw new Error("Cannot allocate a server without players");
  const allocatorUrl = process.env.RIVET_ALLOCATOR_URL?.replace(/\/$/, "");
  if (allocatorUrl) return allocateThroughExternalAdapter(allocatorUrl, region, players);
  if (hasDirectRivetConfiguration()) return allocateDirectlyOnRivet(region, players);
  return allocateDevelopmentServer(region, players);
}

async function allocateThroughExternalAdapter(
  allocatorUrl: string,
  region: RegionDefinition,
  players: QueueEntry[],
): Promise<AllocationResult> {
  const response = await fetch(`${allocatorUrl}/allocate`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${process.env.RIVET_ALLOCATOR_TOKEN ?? ""}`,
    },
    body: JSON.stringify({
      region_id: region.id,
      provider_region: region.providerRegion,
      players: players.map((entry) => ({
        player_id: entry.playerId,
        queue_ticket_id: entry.queueTicketId,
      })),
      build_id: players[0]?.buildId,
      protocol_version: players[0]?.protocolVersion,
    }),
  });
  if (!response.ok) throw new Error(`Rivet allocator failed with HTTP ${response.status}`);
  return normalizeExternalAllocation((await response.json()) as Record<string, unknown>, region, players);
}

function normalizeExternalAllocation(
  body: Record<string, unknown>,
  region: RegionDefinition,
  players: QueueEntry[],
): AllocationResult {
  const rawAssignment = asRecord(body.assignment) ?? body;
  const matchId = readText(rawAssignment, "matchId", "match_id");
  const serverId = readText(rawAssignment, "serverId", "server_id");
  const host = readText(rawAssignment, "host", "hostname");
  const port = readPort(rawAssignment.port);
  const regionId = readText(rawAssignment, "regionId", "region_id") || region.id;
  const regionName = readText(rawAssignment, "regionName", "region_name") || region.displayName;
  const regionShortName =
    readText(rawAssignment, "regionShortName", "region_short_name") || region.shortName;
  const expiresAt = readPositiveNumber(rawAssignment.expiresAt ?? rawAssignment.expires_at);
  const protocolVersion = readPositiveIntegerValue(
    rawAssignment.protocolVersion ?? rawAssignment.protocol_version,
  );
  const serverAuthToken = readText(body, "serverAuthToken", "server_auth_token");
  const rawTickets = asRecord(body.joinTickets ?? body.join_tickets);
  const joinTickets: Record<string, string> = {};
  if (rawTickets) {
    for (const [queueTicketId, ticket] of Object.entries(rawTickets)) {
      if (typeof ticket === "string" && ticket.length >= 16) joinTickets[queueTicketId] = ticket;
    }
  }
  if (!matchId || !serverId || !host || port <= 0) {
    throw new Error("External allocator returned an incomplete server assignment");
  }
  if (!expiresAt || !protocolVersion) {
    throw new Error("External allocator returned invalid expiry or protocol metadata");
  }
  if (!serverAuthToken) throw new Error("External allocator did not return a per-server auth token");
  for (const player of players) {
    if (!joinTickets[player.queueTicketId]) {
      throw new Error(`External allocator did not return a join ticket for ${player.queueTicketId}`);
    }
  }
  return {
    assignment: {
      matchId,
      serverId,
      host,
      port,
      regionId,
      regionName,
      regionShortName,
      expiresAt,
      protocolVersion,
    },
    joinTickets,
    serverAuthToken,
  };
}

async function allocateDirectlyOnRivet(
  region: RegionDefinition,
  players: QueueEntry[],
): Promise<AllocationResult> {
  const matchId = randomUUID();
  const serverId = randomUUID();
  const matchSeed = randomBytes(4).readUInt32BE(0) & 0x7fffffff;
  const gameServerToken = randomBytes(32).toString("base64url");
  const project = requiredEnvironment("RIVET_PROJECT");
  const environment = requiredEnvironment("RIVET_ENVIRONMENT");
  const buildTag = requiredEnvironment("RIVET_GAME_SERVER_BUILD_TAG");
  const controlBaseUrl = requiredEnvironment("PUBLIC_CONTROL_BASE_URL").replace(/\/$/, "");
  const cpu = readPositiveInteger("GAME_SERVER_CPU_MILLICORES", 1000);
  const memory = readPositiveInteger("GAME_SERVER_MEMORY_MB", 1024);
  const sdk = (await import("@rivet-gg/api")) as unknown as {
    RivetClient: new (options?: Record<string, unknown>) => Record<string, unknown>;
  };
  const client = new sdk.RivetClient({
    token: requiredEnvironment("RIVET_ALLOCATOR_CLOUD_TOKEN"),
  });
  const actor = await createRivetActor(client, {
    project,
    environment,
    body: {
      tags: {
        name: "colony-dominion-game-server",
        match_id: matchId,
        server_id: serverId,
        region_id: region.id,
      },
      buildTags: { name: buildTag, current: "true" },
      region: region.providerRegion || undefined,
      network: {
        ports: {
          game: { protocol: "udp", internalPort: 7000 },
          control: { protocol: "http", internalPort: 7001 },
        },
      },
      resources: { cpu, memory },
      environment: {
        MATCH_ID: matchId,
        MATCH_SEED: String(Math.max(matchSeed, 1)),
        SERVER_ID: serverId,
        REGION_ID: region.id,
        BUILD_ID: players[0]?.buildId ?? "",
        PROTOCOL_VERSION: String(players[0]?.protocolVersion ?? 0),
        MAX_PLAYERS: String(readPositiveInteger("MAX_PLAYERS", 6)),
        EXPECTED_PLAYERS: String(players.length),
        CONTROL_BASE_URL: controlBaseUrl,
        GAME_SERVER_AUTH_TOKEN: gameServerToken,
        GAME_PORT: "7000",
        CONTROL_PORT: "7001",
        RANKED_MATCH: process.env.RANKED_MATCH === "0" ? "0" : "1",
      },
    },
  });
  const actorId = actor.id ?? actor.actorId;
  if (!actorId) throw new Error("Rivet actor response did not include an id");
  const gamePort = actor.network?.ports?.game;
  const controlPort = actor.network?.ports?.control;
  const host = gamePort?.host ?? gamePort?.hostname ?? hostFromUrl(gamePort?.url);
  const port = gamePort?.port ?? portFromUrl(gamePort?.url);
  if (!host || !port) throw new Error("Rivet actor response did not include a public UDP endpoint");
  const controlUrl = resolveHttpPortUrl(controlPort);
  if (!controlUrl) throw new Error("Rivet actor response did not include a control endpoint");
  await waitForReady(controlUrl, 30_000);
  return makeAllocation(
    matchId,
    serverId,
    host,
    port,
    region,
    players,
    Date.now() + 90_000,
    gameServerToken,
  );
}

async function createRivetActor(
  client: Record<string, unknown>,
  input: Record<string, unknown>,
): Promise<RivetActorResponse> {
  const actors = client.actors as
    | { create?: (value: Record<string, unknown>) => Promise<unknown> }
    | undefined;
  if (actors?.create) {
    const response = (await actors.create(input)) as Record<string, unknown>;
    return (response.actor ?? response) as RivetActorResponse;
  }
  const actorsCreate = client.actorsCreate as
    | ((value: Record<string, unknown>) => Promise<unknown>)
    | undefined;
  if (actorsCreate) {
    const response = (await actorsCreate.call(client, input)) as Record<string, unknown>;
    return (response.actor ?? response) as RivetActorResponse;
  }
  throw new Error("Installed Rivet SDK does not expose actors.create");
}

async function waitForReady(controlUrl: string, timeoutMs: number): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${controlUrl.replace(/\/$/, "")}/ready`, {
        signal: AbortSignal.timeout(1500),
      });
      if (response.ok) return;
    } catch {
      // Container can take a few seconds to bind its health port.
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error("Allocated game server did not become ready before timeout");
}

function allocateDevelopmentServer(
  region: RegionDefinition,
  players: QueueEntry[],
): AllocationResult {
  if (process.env.NODE_ENV === "production" && process.env.ALLOW_DEV_ALLOCATOR !== "1") {
    throw new Error("Development allocator is disabled in production");
  }
  const host = process.env.DEV_GAME_SERVER_HOST;
  const port = Number(process.env.DEV_GAME_SERVER_PORT ?? 0);
  if (!host || !Number.isInteger(port) || port <= 0) {
    throw new Error(
      "Configure direct Rivet allocation, RIVET_ALLOCATOR_URL, or DEV_GAME_SERVER_HOST/PORT",
    );
  }
  const matchId = randomUUID();
  const serverAuthToken = requiredEnvironment("DEV_GAME_SERVER_AUTH_TOKEN");
  return makeAllocation(
    matchId,
    `dev-${matchId}`,
    host,
    port,
    region,
    players,
    Date.now() + 60_000,
    serverAuthToken,
  );
}

function makeAllocation(
  matchId: string,
  serverId: string,
  host: string,
  port: number,
  region: RegionDefinition,
  players: QueueEntry[],
  expiresAt: number,
  serverAuthToken: string,
): AllocationResult {
  const joinTickets = Object.fromEntries(
    players.map((entry) => [entry.queueTicketId, randomBytes(32).toString("base64url")]),
  );
  return {
    assignment: {
      matchId,
      serverId,
      host,
      port,
      regionId: region.id,
      regionName: region.displayName,
      regionShortName: region.shortName,
      expiresAt,
      protocolVersion: players[0]?.protocolVersion ?? 1,
    },
    joinTickets,
    serverAuthToken,
  };
}

function hasDirectRivetConfiguration(): boolean {
  return Boolean(
    process.env.RIVET_ALLOCATOR_CLOUD_TOKEN &&
      process.env.RIVET_PROJECT &&
      process.env.RIVET_ENVIRONMENT &&
      process.env.RIVET_GAME_SERVER_BUILD_TAG &&
      process.env.PUBLIC_CONTROL_BASE_URL,
  );
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required for direct Rivet allocation`);
  return value;
}

function readPositiveInteger(name: string, fallback: number): number {
  const value = Number(process.env[name] ?? fallback);
  return Number.isInteger(value) && value > 0 ? value : fallback;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}
function readText(record: Record<string, unknown>, primary: string, fallback: string): string {
  const value = record[primary] ?? record[fallback];
  return typeof value === "string" ? value.trim() : "";
}
function readPort(value: unknown): number {
  const port = Number(value ?? 0);
  return Number.isInteger(port) && port > 0 && port <= 65535 ? port : 0;
}
function readPositiveNumber(value: unknown): number {
  const number = Number(value ?? 0);
  return Number.isFinite(number) && number > 0 ? number : 0;
}
function readPositiveIntegerValue(value: unknown): number {
  const number = Number(value ?? 0);
  return Number.isInteger(number) && number > 0 ? number : 0;
}
function resolveHttpPortUrl(port?: ActorPort): string {
  if (!port) return "";
  if (port.url) return port.url.replace(/\/$/, "");
  const host = port.host ?? port.hostname;
  if (!host || !port.port) return "";
  return `http://${host}:${port.port}`;
}

function hostFromUrl(value?: string): string {
  if (!value) return "";
  try {
    return new URL(value).hostname;
  } catch {
    return "";
  }
}
function portFromUrl(value?: string): number {
  if (!value) return 0;
  try {
    const url = new URL(value);
    if (url.port) return Number(url.port);
    return url.protocol === "https:" ? 443 : 80;
  } catch {
    return 0;
  }
}
