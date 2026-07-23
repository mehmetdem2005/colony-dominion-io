// Colony Dominion.io — Edgegap matchmaking Edge Function.
//
// Replaces the Rivet control plane. The player (authenticated with a Supabase
// JWT) asks to join a match; this function asks Edgegap's Arbitrium API to
// deploy the game-server container (ghcr.io/.../colony-dominion-server) on the
// edge node nearest the player's IP, then returns the DIRECT public ip:port.
// The Godot client connects straight to it over ENet/UDP — no gateway hop.
//
// The Edgegap API token never reaches the client; it lives only here as the
// EDGEGAP_API_TOKEN secret. Deploy this function with JWT verification ON so
// only signed-in players can request a server.
//
// Required function secrets / env:
//   EDGEGAP_API_TOKEN    - Edgegap API token (from app.edgegap.com)
//   EDGEGAP_APP_NAME     - the Edgegap application name for the server image
//   EDGEGAP_APP_VERSION  - the Edgegap application version name
//   GAME_BUILD_ID        - build id injected into the server (match compat)
//   GAME_MAX_PLAYERS     - max players per match (default 10)

const EDGEGAP_API = "https://api.edgegap.com/v1";
const READY = "Status.READY";
const ERRORLIKE = new Set(["Status.ERROR", "Status.TERMINATED"]);
const GAME_PORT_NAME = "game"; // must match the port name configured in Edgegap
const JSON_HEADERS = new Headers({
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
});

type RegionTarget = {
  latitude: number;
  longitude: number;
  displayName: string;
  shortName: string;
};

// Manual targets are deliberately resolved server-side. The client may select
// an id, but it cannot inject arbitrary coordinates into the Edgegap request.
// The real Edgegap edge locations. Each id maps to that city's coordinates;
// Edgegap places the server on the node nearest those coordinates, so selecting
// an id pins the match to that actual city (real, measurably different ping).
// Continent-level targets. Each id points at a representative coordinate on that
// continent; Edgegap places the server on the nearest edge node to it. The free
// tier only has edges on these four continents (Europe, North/South America,
// Asia) — there is no Africa / Middle East / Oceania node, so those are not
// offered rather than silently routing the player to Europe.
const REGION_TARGETS: Record<string, RegionTarget> = {
  "avrupa": { latitude: 50.1109, longitude: 8.6821, displayName: "Avrupa", shortName: "AVR" },
  "kuzey_amerika": {
    latitude: 39.8283,
    longitude: -98.5795,
    displayName: "Kuzey Amerika",
    shortName: "K.AM",
  },
  "asya": { latitude: 1.3521, longitude: 103.8198, displayName: "Asya", shortName: "ASYA" },
  "guney_amerika": {
    latitude: -23.5505,
    longitude: -46.6333,
    displayName: "Güney Amerika",
    shortName: "G.AM",
  },
};

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: JSON_HEADERS });
}

function env(name: string): string {
  return (Deno.env.get(name) ?? "").trim();
}

function randomHex(byteCount: number): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(byteCount)), (b) =>
    b.toString(16).padStart(2, "0")).join("");
}

function edgegapHeaders(): HeadersInit {
  // Edgegap expects "token <api-token>" in the Authorization header.
  const raw = env("EDGEGAP_API_TOKEN");
  const value = raw.toLowerCase().startsWith("token ") ? raw : `token ${raw}`;
  return { authorization: value, "content-type": "application/json" };
}

function normalizeIpv4(value: string): string {
  const parts = value.split(".");
  if (parts.length !== 4) return "";
  const numbers = parts.map((part) => Number(part));
  if (numbers.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) return "";
  return numbers.join(".");
}

function normalizeIp(value: string): string {
  let candidate = value.trim().replace(/^for=/i, "").replace(/^["']|["']$/g, "");
  if (candidate.startsWith("[") && candidate.includes("]")) {
    candidate = candidate.slice(1, candidate.indexOf("]"));
  }
  const mappedV4 = candidate.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/i)?.[1] ?? "";
  if (mappedV4) return normalizeIpv4(mappedV4);
  const ipv4 = normalizeIpv4(candidate);
  if (ipv4) return ipv4;
  if (
    candidate.length <= 64 &&
    candidate.includes(":") &&
    /^[0-9a-f:]+$/i.test(candidate)
  ) {
    return candidate.toLowerCase();
  }
  return "";
}

function clientIp(request: Request): string {
  // Supabase/Cloudflare may expose the original address under different
  // trusted proxy headers. Validate every candidate before passing it to
  // Edgegap so a malformed header cannot silently force a remote deployment.
  const headerNames = [
    "cf-connecting-ip",
    "x-real-ip",
    "x-forwarded-for",
    "true-client-ip",
  ];
  for (const headerName of headerNames) {
    const raw = request.headers.get(headerName) ?? "";
    for (const part of raw.split(",")) {
      const normalized = normalizeIp(part);
      if (normalized) return normalized;
    }
  }
  return "";
}

function normalizeRegionId(value: unknown): string {
  const cleaned = String(value ?? "").trim().toLowerCase();
  return /^[a-z0-9-]{2,32}$/.test(cleaned) ? cleaned : "auto";
}

function requestedRegion(payload: Record<string, unknown>): string {
  const selected = normalizeRegionId(payload.selected_region_id);
  if (selected !== "auto" && REGION_TARGETS[selected]) return selected;
  const preferred = normalizeRegionId(payload.region_preference);
  if (preferred !== "auto" && REGION_TARGETS[preferred]) return preferred;
  return "auto";
}

async function requestObject(request: Request): Promise<Record<string, unknown> | null> {
  const parsed = await request.json().catch(() => null);
  if (parsed === null || Array.isArray(parsed) || typeof parsed !== "object") return null;
  return parsed as Record<string, unknown>;
}

function deploymentRegionId(payload: Record<string, unknown>): string {
  const tags = Array.isArray(payload.tags) ? payload.tags : [];
  for (const tag of tags) {
    const match = String(tag).match(/^region-([a-z0-9-]{2,32})$/);
    if (match) return normalizeRegionId(match[1]);
  }
  return "auto";
}

function routeParts(request: Request): string[] {
  const path = new URL(request.url).pathname;
  const marker = "/matchmaking";
  const index = path.indexOf(marker);
  if (index < 0) return [];
  return path.slice(index + marker.length).split("/").map((p) => p.trim()).filter(Boolean);
}

// Verify the caller is a signed-in Supabase user (the function is deployed with
// --no-verify-jwt so /health stays public, so /join must check auth itself).
async function authenticatedUserId(request: Request): Promise<string> {
  const auth = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+.+/i.test(auth)) return "";
  const base = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!base || !anon) return "";
  const response = await fetch(`${base}/auth/v1/user`, {
    headers: { apikey: anon, authorization: auth },
  }).catch(() => null);
  if (!response?.ok) return "";
  const payload = await response.json().catch(() => ({})) as Record<string, unknown>;
  const userId = String(payload.id ?? "").trim();
  return /^[A-Za-z0-9_-]{16,128}$/.test(userId) ? userId : "";
}

function displayName(payload: Record<string, unknown>): string {
  const cleaned = String(payload.display_name ?? "")
    .replace(/[\u0000-\u001f\u007f]/g, "")
    .trim()
    .slice(0, 24);
  return cleaned || "Player";
}

function gameMaxPlayers(): number {
  const configured = Number.parseInt(env("GAME_MAX_PLAYERS"), 10);
  if (!Number.isInteger(configured)) return 10;
  return Math.min(Math.max(configured, 1), 10);
}

// POST /join — deploy a server near the player and return a request handle.
async function join(request: Request): Promise<Response> {
  const appName = env("EDGEGAP_APP_NAME");
  const versionName = env("EDGEGAP_APP_VERSION");
  if (!env("EDGEGAP_API_TOKEN") || !appName || !versionName) {
    return json({ ok: false, error: "matchmaking_not_configured" }, 503);
  }
  const authenticatedPlayerId = await authenticatedUserId(request);
  if (!authenticatedPlayerId) {
    return json({ ok: false, error: "authentication_required" }, 401);
  }
  const ip = clientIp(request);
  if (!ip) return json({ ok: false, error: "client_ip_unavailable" }, 400);
  const requestPayload = await requestObject(request);
  if (requestPayload === null) {
    return json({ ok: false, error: "invalid_request_payload" }, 400);
  }
  const claimedPlayerId = String(requestPayload.player_id ?? "").trim();
  if (claimedPlayerId && claimedPlayerId !== authenticatedPlayerId) {
    return json({ ok: false, error: "player_identity_mismatch" }, 403);
  }
  const trustedDisplayName = displayName(requestPayload);
  const regionId = requestedRegion(requestPayload);
  const regionTarget = REGION_TARGETS[regionId];

  // The game server authenticates each client with a single-use join ticket,
  // authenticated player id, and match/server identity. Generate them here,
  // inject the trusted claims into the server, and return only the client claim.
  const matchId = crypto.randomUUID();
  const serverId = crypto.randomUUID();
  const joinTicket = randomHex(24);
  const maxPlayers = gameMaxPlayers();
  const buildId = env("GAME_BUILD_ID") || "colony";

  const body: Record<string, unknown> = {
    app_name: appName,
    version_name: versionName,
    ip_list: [ip],
    skip_telemetry: true,
    tags: ["colony", `region-${regionId}`],
    env_vars: [
      { key: "MATCH_ID", value: matchId },
      { key: "SERVER_ID", value: serverId },
      { key: "BUILD_ID", value: buildId },
      { key: "MAX_PLAYERS", value: String(maxPlayers) },
      { key: "EXPECTED_PLAYERS", value: "1" },
      { key: "HUMAN_PLAYER_COUNT", value: "1" },
      { key: "BOT_COUNT", value: String(maxPlayers - 1) },
      { key: "RANKED_MATCH", value: "0" },
      { key: "NETWORK_TRANSPORT", value: "enet" },
      { key: "GAME_PORT", value: "20000" },
      { key: "EXPECTED_JOIN_TICKET", value: joinTicket, is_hidden: true },
      { key: "EXPECTED_PLAYER_ID", value: authenticatedPlayerId, is_hidden: true },
      { key: "EXPECTED_DISPLAY_NAME", value: trustedDisplayName },
    ],
  };
  if (regionTarget) {
    body.location = {
      latitude: regionTarget.latitude,
      longitude: regionTarget.longitude,
    };
  }
  const response = await fetch(`${EDGEGAP_API}/deploy`, {
    method: "POST",
    headers: edgegapHeaders(),
    body: JSON.stringify(body),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    console.error("Edgegap deploy failed", response.status, payload);
    return json({ ok: false, error: "deploy_failed" }, 502);
  }
  const requestId = String(payload.request_id ?? "").trim();
  if (!requestId) return json({ ok: false, error: "deploy_no_request_id" }, 502);
  return json({
    ok: true,
    request_id: requestId,
    join_ticket: joinTicket,
    match_id: matchId,
    server_id: serverId,
    build_id: buildId,
    region_id: regionId,
    poll_interval_ms: 1500,
  });
}

// GET /status/{request_id} — poll Edgegap; when READY return the direct ip:port.
async function status(requestId: string): Promise<Response> {
  if (!/^[A-Za-z0-9_-]{4,128}$/.test(requestId)) {
    return json({ ok: false, error: "invalid_request_id" }, 400);
  }
  const response = await fetch(`${EDGEGAP_API}/status/${encodeURIComponent(requestId)}`, {
    headers: edgegapHeaders(),
  });
  const payload = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (!response.ok) return json({ ok: false, error: "status_failed" }, 502);

  const current = String(payload.current_status ?? "");
  if (ERRORLIKE.has(current)) {
    return json({ ok: false, ready: false, error: "deployment_failed", status: current }, 200);
  }
  if (current !== READY) {
    return json({ ok: true, ready: false, status: current }, 200);
  }

  const publicIp = String(payload.public_ip ?? "").trim();
  const ports = (payload.ports ?? {}) as Record<string, { external?: number; protocol?: string }>;
  // Prefer the named game port; otherwise take the first mapping.
  const mapping = ports[GAME_PORT_NAME] ?? Object.values(ports)[0];
  const externalPort = Number(mapping?.external ?? 0);
  if (!publicIp || !Number.isInteger(externalPort) || externalPort <= 0 || externalPort > 65535) {
    return json({ ok: false, error: "invalid_deployment_endpoint" }, 502);
  }

  const regionId = deploymentRegionId(payload);
  const regionTarget = REGION_TARGETS[regionId];
  const city = String(payload.city ?? "").trim();
  const country = String(payload.country ?? "").trim();
  const actualLocation = [city, country].filter(Boolean).join(", ");
  return json({
    ok: true,
    ready: true,
    assignment: {
      transport: "enet",
      host: publicIp,
      port: externalPort,
      request_id: requestId,
      region_id: regionId,
      region_name: actualLocation || regionTarget?.displayName || "Edgegap — En Yakın",
      region_short_name: regionTarget?.shortName ?? "EDGE",
    },
  });
}

// DELETE /cancel/{request_id} — stop a deployment the player abandoned.
async function cancel(requestId: string): Promise<Response> {
  if (!/^[A-Za-z0-9_-]{4,128}$/.test(requestId)) {
    return json({ ok: false, error: "invalid_request_id" }, 400);
  }
  await fetch(`${EDGEGAP_API}/stop/${encodeURIComponent(requestId)}`, {
    method: "DELETE",
    headers: edgegapHeaders(),
  }).catch(() => undefined);
  return json({ ok: true });
}

Deno.serve(async (request) => {
  try {
    const parts = routeParts(request);
    const action = parts[0] ?? "health";
    const requestId = parts[1] ?? "";
    if (request.method === "GET" && action === "health") {
      return json({
        ok: true,
        service: "colony-edgegap-matchmaking",
        configured: Boolean(env("EDGEGAP_API_TOKEN") && env("EDGEGAP_APP_NAME")),
      });
    }
    if (request.method === "POST" && action === "join") return await join(request);
    if (request.method === "GET" && action === "status") return await status(requestId);
    if (request.method === "DELETE" && action === "cancel") return await cancel(requestId);
    return json({ ok: false, error: "not_found" }, 404);
  } catch (error) {
    console.error("matchmaking error", error instanceof Error ? error.message : String(error));
    return json({ ok: false, error: "matchmaking_unavailable" }, 503);
  }
});
