import { createHash, randomBytes, randomUUID } from "node:crypto";
import type { QueueEntry, RegionDefinition, ServerAssignment } from "./types.js";

export type AllocationResult = {
  assignment: Omit<ServerAssignment, "joinTicket">;
  joinTickets: Record<string, string>;
  serverAuthToken: string;
};

type ExternalAllocationResponse = {
  assignment?: Record<string, unknown>;
  join_tickets?: Record<string, unknown>;
  joinTickets?: Record<string, unknown>;
  server_auth_token?: unknown;
  serverAuthToken?: unknown;
};

export async function allocateGameServer(
  region: RegionDefinition,
  players: QueueEntry[],
): Promise<AllocationResult> {
  if (players.length === 0) throw new Error("Cannot allocate a server without players");
  const allocatorUrl = process.env.RIVET_ALLOCATOR_URL?.trim().replace(/\/$/, "");
  if (allocatorUrl) return allocateThroughExternalAdapter(allocatorUrl, region, players);
  return allocateDevelopmentServer(region, players);
}

async function allocateThroughExternalAdapter(
  allocatorUrl: string,
  region: RegionDefinition,
  players: QueueEntry[],
): Promise<AllocationResult> {
  assertAllocatorUrlAllowed(allocatorUrl);
  const token = requiredEnvironment("RIVET_ALLOCATOR_TOKEN");
  const buildId = players[0]?.buildId ?? "";
  const protocolVersion = players[0]?.protocolVersion ?? 0;
  if (!buildId || protocolVersion <= 0) throw new Error("Allocation candidates have invalid build metadata");
  for (const player of players) {
    if (player.buildId !== buildId || player.protocolVersion !== protocolVersion) {
      throw new Error("Allocation candidates do not share the same build and protocol version");
    }
  }
  const allocationKey = createHash("sha256")
    .update(JSON.stringify({
      regionId: region.id,
      buildId,
      protocolVersion,
      queueTicketIds: players.map((entry) => entry.queueTicketId).sort(),
    }))
    .digest("hex");
  const requestBody = {
    allocation_key: allocationKey,
    region_id: region.id,
    provider_region: region.providerRegion ?? "",
    players: players.map((entry) => ({
      player_id: entry.playerId,
      queue_ticket_id: entry.queueTicketId,
    })),
    build_id: buildId,
    protocol_version: protocolVersion,
  };

  let lastError: unknown = null;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await fetch(`${allocatorUrl}/allocate`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${token}`,
          "x-colony-allocation-key": allocationKey,
        },
        body: JSON.stringify(requestBody),
        signal: AbortSignal.timeout(65_000),
      });
      const responseText = await response.text();
      if (!response.ok) {
        const transient = response.status === 429 || response.status >= 500;
        const detail = responseText.slice(0, 1000).replace(/\s+/g, " ");
        const error = new Error(`External allocator failed with HTTP ${response.status}: ${detail}`);
        if (!transient || attempt === 3) throw error;
        lastError = error;
      } else {
        let parsed: unknown;
        try {
          parsed = responseText ? JSON.parse(responseText) : null;
        } catch {
          throw new Error("External allocator returned invalid JSON");
        }
        return normalizeExternalAllocation(parsed, region, players);
      }
    } catch (error) {
      lastError = error;
      if (attempt === 3 || !isRetryableNetworkError(error)) throw error;
    }
    await new Promise((resolve) => setTimeout(resolve, attempt * 750));
  }
  throw lastError instanceof Error ? lastError : new Error("External allocator failed");
}

function normalizeExternalAllocation(
  value: unknown,
  region: RegionDefinition,
  players: QueueEntry[],
): AllocationResult {
  const body = (asRecord(value) ?? {}) as ExternalAllocationResponse;
  const rawAssignment = asRecord(body.assignment) ?? asRecord(value) ?? {};
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
  const serverAuthToken = readText(
    asRecord(value) ?? {},
    "serverAuthToken",
    "server_auth_token",
  );
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

function allocateDevelopmentServer(
  region: RegionDefinition,
  players: QueueEntry[],
): AllocationResult {
  if (process.env.NODE_ENV === "production" && process.env.ALLOW_DEV_ALLOCATOR !== "1") {
    throw new Error("External game-server allocator is not configured");
  }
  const host = process.env.DEV_GAME_SERVER_HOST;
  const port = Number(process.env.DEV_GAME_SERVER_PORT ?? 0);
  if (!host || !Number.isInteger(port) || port <= 0) {
    throw new Error("Configure RIVET_ALLOCATOR_URL or DEV_GAME_SERVER_HOST/PORT");
  }
  const matchId = randomUUID();
  const serverAuthToken = requiredEnvironment("DEV_GAME_SERVER_AUTH_TOKEN");
  const joinTickets = Object.fromEntries(
    players.map((entry) => [entry.queueTicketId, randomBytes(32).toString("base64url")]),
  );
  return {
    assignment: {
      matchId,
      serverId: `dev-${matchId}`,
      host,
      port,
      regionId: region.id,
      regionName: region.displayName,
      regionShortName: region.shortName,
      expiresAt: Date.now() + 60_000,
      protocolVersion: players[0]?.protocolVersion ?? 1,
    },
    joinTickets,
    serverAuthToken,
  };
}

function assertAllocatorUrlAllowed(value: string): void {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("RIVET_ALLOCATOR_URL is not a valid URL");
  }
  if (url.protocol === "https:") return;
  const localHost = ["localhost", "127.0.0.1", "allocator"].includes(url.hostname);
  if (url.protocol === "http:" && (localHost || process.env.ALLOW_INSECURE_ALLOCATOR_URL === "1")) return;
  throw new Error("RIVET_ALLOCATOR_URL must use HTTPS outside the private Docker network");
}

function isRetryableNetworkError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  if (error.name === "TimeoutError" || error.name === "AbortError") return true;
  return error instanceof TypeError || /HTTP (429|5\d\d)/.test(error.message);
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required for game-server allocation`);
  return value;
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
