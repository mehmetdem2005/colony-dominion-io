import { createHash, randomUUID } from "node:crypto";
import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { createClient } from "rivetkit/client";
import { z } from "zod";
import { allocateGameServer } from "./allocator.js";
import { requireSupabaseAuth, type AuthVariables } from "./auth.js";
import { registry } from "./registry.js";
import { findRegion, loadRegions } from "./regions.js";
import type {
  QueueStatus,
  ServerAssignment,
  SessionTicketRecord,
} from "./types.js";

const port = Number(process.env.RIVET_PORT ?? process.env.PORT ?? 3000);
const baseUrl = process.env.INTERNAL_BASE_URL ?? `http://127.0.0.1:${port}`;
const actorClient = createClient<typeof registry>(`${baseUrl}/api/rivet`);
const app = new Hono<{ Variables: AuthVariables }>();
const regions = loadRegions();
const minPlayers = readBoundedIntegerEnvironment("MIN_PLAYERS", 2, 1, 10);
const maxPlayers = readBoundedIntegerEnvironment("MAX_PLAYERS", 10, minPlayers, 10);
const queueTtlMs = Math.max(30, Number(process.env.QUEUE_TTL_SECONDS ?? 120)) * 1000;
const requiredBuildId = process.env.SUPPORTED_BUILD_ID ?? "";
const requiredProtocolVersion = Number(process.env.PROTOCOL_VERSION ?? 0);
const supabaseUrl = (process.env.SUPABASE_URL ?? "").replace(/\/$/, "");
const supabaseSecretKey = process.env.SUPABASE_SECRET_KEY ?? "";

const joinSchema = z.object({
  player_id: z.string().uuid(),
  display_name: z.string().trim().min(2).max(24),
  region_preference: z.string().trim().min(1).max(32),
  selected_region_id: z.string().trim().min(1).max(32).optional(),
  build_id: z.string().trim().min(1).max(96),
  protocol_version: z.number().int().positive(),
});

const matchResultSchema = z.object({
  match_id: z.string().uuid(),
  server_id: z.string().trim().min(2).max(128),
  region_id: z.string().trim().min(1).max(32),
  build_id: z.string().trim().min(1).max(96),
  protocol_version: z.number().int().positive(),
  started_at_ms: z.number().int().positive(),
  ended_at_ms: z.number().int().positive(),
  termination_reason: z.string().trim().min(1).max(64),
  ranked: z.boolean().default(true),
  participants: z.array(
    z.object({
      player_id: z.string().uuid(),
      team_id: z.number().int().min(0).max(31),
      placement: z.number().int().min(1).max(32),
      score: z.number().int().min(0),
      disconnected: z.boolean(),
    }),
  ).max(32),
});

const consumeSchema = z.object({
  join_ticket: z.string().trim().min(16).max(256),
  player_id: z.string().uuid(),
  match_id: z.string().uuid(),
  server_id: z.string().trim().min(2).max(128),
  build_id: z.string().trim().min(1).max(96),
  protocol_version: z.number().int().positive(),
});

app.all("/api/rivet/*", (c) => registry.handler(c.req.raw));

app.get("/v1/health", (c) =>
  c.json({ ok: true, service: "colony-dominion-rivet-control", now: Date.now() }),
);
app.get("/v1/health/config", (c) => {
  const checks = {
    supabase_url: Boolean(supabaseUrl),
    supported_build_id: Boolean(requiredBuildId),
    protocol_version: requiredProtocolVersion > 0,
    per_server_auth: true,
    supabase_server_write: Boolean(supabaseSecretKey),
    allocator: Boolean(
      process.env.RIVET_ALLOCATOR_URL ||
        process.env.DEV_GAME_SERVER_HOST ||
        (process.env.RIVET_ALLOCATOR_CLOUD_TOKEN &&
          process.env.RIVET_PROJECT &&
          process.env.RIVET_ENVIRONMENT &&
          process.env.RIVET_GAME_SERVER_BUILD_TAG &&
          process.env.PUBLIC_CONTROL_BASE_URL),
    ),
    regions: regions.some((region) => region.enabled),
  };
  return c.json({
    ready: Object.values(checks).every(Boolean),
    checks,
    limits: {
      min_players: minPlayers,
      max_players: maxPlayers,
      queue_ttl_seconds: queueTtlMs / 1000,
    },
  });
});

app.get("/v1/health/ping", (c) =>
  c.json({ ok: true, now: Date.now(), region: process.env.RIVET_REGION ?? "unknown" }),
);
app.get("/v1/regions", (c) =>
  c.json({
    regions: regions.map((region) => ({
      id: region.id,
      display_name: region.displayName,
      short_name: region.shortName,
      probe_url: region.probeUrl,
      enabled: region.enabled,
    })),
  }),
);

app.use("/v1/matchmaking/*", requireSupabaseAuth);

app.post("/v1/matchmaking/join", async (c) => {
  const parsed = joinSchema.safeParse(await c.req.json().catch(() => null));
  if (!parsed.success) return c.json({ error: "Invalid matchmaking request" }, 400);
  const auth = c.get("auth");
  if (!auth.sub || auth.sub !== parsed.data.player_id) {
    return c.json({ error: "JWT subject does not match player_id" }, 403);
  }
  if (requiredBuildId && parsed.data.build_id !== requiredBuildId) {
    return c.json({ error: "Client build is not supported", update_required: true }, 409);
  }
  if (
    requiredProtocolVersion > 0 &&
    parsed.data.protocol_version !== requiredProtocolVersion
  ) {
    return c.json({ error: "Network protocol version mismatch", update_required: true }, 409);
  }

  const requestedRegion =
    parsed.data.region_preference === "auto"
      ? parsed.data.selected_region_id ?? regions[0]?.id ?? "eu"
      : parsed.data.region_preference;
  const enabledRegions = regions.filter((candidate) => candidate.enabled);
  if (enabledRegions.length === 0) return c.json({ error: "No regions available" }, 503);
  const region = findRegion(enabledRegions, requestedRegion);
  const actorInstance = await actorClient.matchmaker.getOrCreate();
  await actorInstance.expireStale(Date.now() - queueTtlMs);

  const queueTicketId = `${region.id}.${randomUUID()}`;
  const status = await actorInstance.join(region.id, {
    queueTicketId,
    playerId: parsed.data.player_id,
    displayName: parsed.data.display_name,
    regionPreference: parsed.data.region_preference,
    buildId: parsed.data.build_id,
    protocolVersion: parsed.data.protocol_version,
    joinedAt: Date.now(),
    lastHeartbeatAt: Date.now(),
  });

  await attemptAllocation(actorInstance, region.id);
  return c.json(toPublicStatus(await actorInstance.getStatus(status.queue_ticket_id)));
});

app.get("/v1/matchmaking/status/:ticket", async (c) => {
  const queueTicketId = c.req.param("ticket");
  const regionId = extractRegionId(queueTicketId);
  if (!regionId) return c.json({ error: "Invalid queue ticket" }, 400);
  const actorInstance = await actorClient.matchmaker.getOrCreate();
  const auth = c.get("auth");
  if (!auth.sub || !(await actorInstance.isTicketOwner(queueTicketId, auth.sub))) {
    return c.json({ error: "Queue ticket does not belong to this user" }, 403);
  }
  await actorInstance.expireStale(Date.now() - queueTtlMs);
  const status = await actorInstance.heartbeat(queueTicketId);
  await attemptAllocation(actorInstance, regionId);
  return c.json(toPublicStatus(await actorInstance.getStatus(status.queue_ticket_id)));
});

app.delete("/v1/matchmaking/:ticket", async (c) => {
  const queueTicketId = c.req.param("ticket");
  if (!extractRegionId(queueTicketId)) return c.json({ error: "Invalid queue ticket" }, 400);
  const actorInstance = await actorClient.matchmaker.getOrCreate();
  const auth = c.get("auth");
  if (!auth.sub || !(await actorInstance.isTicketOwner(queueTicketId, auth.sub))) {
    return c.json({ error: "Queue ticket does not belong to this user" }, 403);
  }
  return c.json(toPublicStatus(await actorInstance.cancel(queueTicketId)));
});

app.post("/v1/internal/matches/result", async (c) => {
  if (!supabaseUrl || !supabaseSecretKey) {
    return c.json({ ok: false, error: "supabase_server_write_not_configured" }, 503);
  }
  const parsed = matchResultSchema.safeParse(await c.req.json().catch(() => null));
  if (!parsed.success) return c.json({ ok: false, error: "invalid_match_result" }, 400);
  const actorInstance = await actorClient.matchmaker.getOrCreate();
  const tokenHash = hashAuthorization(c.req.header("authorization") ?? "");
  const authorized = await actorInstance.authorizeServer(
    parsed.data.server_id,
    parsed.data.match_id,
    tokenHash,
    Date.now(),
    false,
  );
  if (!authorized) return c.json({ ok: false, error: "unauthorized_game_server" }, 401);
  if (requiredBuildId && parsed.data.build_id !== requiredBuildId) {
    return c.json({ ok: false, error: "unsupported_server_build" }, 409);
  }
  if (requiredProtocolVersion > 0 && parsed.data.protocol_version !== requiredProtocolVersion) {
    return c.json({ ok: false, error: "server_protocol_mismatch" }, 409);
  }
  const rpcResponse = await fetch(
    `${supabaseUrl}/rest/v1/rpc/record_authoritative_match_result`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        apikey: supabaseSecretKey,
        authorization: `Bearer ${supabaseSecretKey}`,
      },
      body: JSON.stringify({
        p_match_id: parsed.data.match_id,
        p_rivet_server_id: parsed.data.server_id,
        p_region: parsed.data.region_id,
        p_build_version: parsed.data.build_id,
        p_protocol_version: parsed.data.protocol_version,
        p_started_at: new Date(parsed.data.started_at_ms).toISOString(),
        p_ended_at: new Date(parsed.data.ended_at_ms).toISOString(),
        p_termination_reason: parsed.data.termination_reason,
        p_participants: parsed.data.participants,
        p_ranked: parsed.data.ranked,
      }),
    },
  );
  if (!rpcResponse.ok) {
    const detail = await rpcResponse.text();
    console.error("Supabase match result write failed", rpcResponse.status, detail);
    return c.json({ ok: false, error: "match_result_write_failed" }, 502);
  }
  await actorInstance.authorizeServer(
    parsed.data.server_id,
    parsed.data.match_id,
    tokenHash,
    Date.now(),
    true,
  );
  await actorInstance.releaseMatch(parsed.data.match_id, Date.now());
  const resultBody = await rpcResponse.json().catch(() => ({ ok: true }));
  return c.json({ ok: true, result: resultBody });
});

app.post("/v1/internal/sessions/consume", async (c) => {
  const parsed = consumeSchema.safeParse(await c.req.json().catch(() => null));
  if (!parsed.success) return c.json({ ok: false, error: "invalid_ticket_request" }, 400);
  const actorInstance = await actorClient.matchmaker.getOrCreate();
  const authorized = await actorInstance.authorizeServer(
    parsed.data.server_id,
    parsed.data.match_id,
    hashAuthorization(c.req.header("authorization") ?? ""),
    Date.now(),
    false,
  );
  if (!authorized) return c.json({ ok: false, error: "unauthorized_game_server" }, 401);
  const result = await actorInstance.consumeSessionTicket({
    ticketHash: hashTicket(parsed.data.join_ticket),
    playerId: parsed.data.player_id,
    matchId: parsed.data.match_id,
    serverId: parsed.data.server_id,
    buildId: parsed.data.build_id,
    protocolVersion: parsed.data.protocol_version,
    now: Date.now(),
  });
  if (!result.ok) return c.json(result, 403);
  return c.json(result, 200);
});

async function attemptAllocation(
  actorInstance: Awaited<ReturnType<typeof actorClient.matchmaker.getOrCreate>>,
  regionId: string,
): Promise<void> {
  const queueSize = await actorInstance.queueSize(regionId);
  if (queueSize < minPlayers) return;
  const candidates = await actorInstance.takeCandidates(
    regionId,
    Math.min(queueSize, maxPlayers),
  );
  if (candidates.length < minPlayers) {
    await actorInstance.restoreCandidates(regionId, candidates);
    return;
  }
  try {
    const allocation = await allocateGameServer(findRegion(regions, regionId), candidates);
    await actorInstance.registerServerCredential({
      matchId: allocation.assignment.matchId,
      serverId: allocation.assignment.serverId,
      tokenHash: hashTicket(allocation.serverAuthToken),
      expiresAt: Date.now() + 4 * 60 * 60 * 1000,
      resultRecordedAt: 0,
    });
    const records: SessionTicketRecord[] = candidates.map((entry) => {
      const rawTicket = allocation.joinTickets[entry.queueTicketId] ?? "";
      return {
        queueTicketId: entry.queueTicketId,
        ticketHash: hashTicket(rawTicket),
        playerId: entry.playerId,
        displayName: entry.displayName,
        matchId: allocation.assignment.matchId,
        serverId: allocation.assignment.serverId,
        buildId: entry.buildId,
        protocolVersion: entry.protocolVersion,
        expiresAt: allocation.assignment.expiresAt,
        consumedAt: 0,
      };
    });
    await actorInstance.registerSessionTickets(records);
    await actorInstance.assign(
      candidates.map((entry) => entry.queueTicketId),
      allocation.assignment,
      allocation.joinTickets,
    );
  } catch (error) {
    await actorInstance.restoreCandidates(regionId, candidates);
    console.error("Game server allocation failed", error);
  }
}

function extractRegionId(queueTicketId: string): string {
  const separator = queueTicketId.indexOf(".");
  return separator > 0 ? queueTicketId.slice(0, separator) : "";
}

function toPublicStatus(status: QueueStatus): Record<string, unknown> {
  if (status.status !== "assigned") return status;
  return {
    status: status.status,
    queue_ticket_id: status.queue_ticket_id,
    assignment: toPublicAssignment(status.assignment),
  };
}

function toPublicAssignment(assignment: ServerAssignment): Record<string, unknown> {
  return {
    match_id: assignment.matchId,
    server_id: assignment.serverId,
    host: assignment.host,
    port: assignment.port,
    join_ticket: assignment.joinTicket,
    region_id: assignment.regionId,
    region_name: assignment.regionName,
    region_short_name: assignment.regionShortName,
    expires_at: assignment.expiresAt,
    protocol_version: assignment.protocolVersion,
  };
}

function readBoundedIntegerEnvironment(
  name: string,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const raw = process.env[name]?.trim();
  if (!raw) return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${name} must be an integer between ${minimum} and ${maximum}`);
  }
  return value;
}

function hashTicket(ticket: string): string {
  return createHash("sha256").update(ticket, "utf8").digest("hex");
}

function hashAuthorization(authorization: string): string {
  if (!authorization.startsWith("Bearer ")) return "";
  return hashTicket(authorization.slice("Bearer ".length));
}

serve({ fetch: app.fetch, port });
console.log(`Colony Dominion control plane listening on ${port}`);
