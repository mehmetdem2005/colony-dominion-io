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
//   SUPABASE_SERVICE_ROLE_KEY - lobby RPC/table access (injected by Supabase)
//
// Online play is shared-lobby-only. If the lobby layer is unavailable, /join
// fails with 503 and the client retries. It must never silently create a private
// one-player deployment, because that turns an infrastructure fault into two
// players being placed in different matches.

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

// Targets are resolved server-side: the client picks an id, never coordinates.
const REGION_TARGETS: Record<string, RegionTarget> = {
  // The ten real Edgegap edge cities, taken from GET /v1/locations. These
  // replace the old continent centroids: pointing at a continent's midpoint
  // sent a Turkish player's server to whatever node happened to be nearest to
  // a spot in the North Sea, when Frankfurt was the answer all along.
  "frankfurt": { latitude: 50.08, longitude: 8.66, displayName: "Frankfurt", shortName: "FRA" },
  "paris": { latitude: 48.86, longitude: 2.33, displayName: "Paris", shortName: "PAR" },
  "newark": { latitude: 40.86, longitude: -74.14, displayName: "New York", shortName: "NY" },
  "chicago": { latitude: 42.1187, longitude: -88.1955, displayName: "Chicago", shortName: "CHI" },
  "dallas": { latitude: 32.93, longitude: -96.66, displayName: "Dallas", shortName: "DAL" },
  "seattle": { latitude: 47.6, longitude: -122.33, displayName: "Seattle", shortName: "SEA" },
  "fremont": {
    latitude: 37.54,
    longitude: -122.01,
    displayName: "San Francisco",
    shortName: "SF",
  },
  "sao_paulo": {
    latitude: -23.55,
    longitude: -46.64,
    displayName: "Sao Paulo",
    shortName: "SAO",
  },
  "mumbai": { latitude: 18.94, longitude: 72.84, displayName: "Mumbai", shortName: "MUM" },
  "singapore": { latitude: 1.23, longitude: 103.83, displayName: "Singapur", shortName: "SGP" },
};

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: JSON_HEADERS });
}

function env(name: string): string {
  return (Deno.env.get(name) ?? "").trim();
}

function edgegapHeaders(): HeadersInit {
  // Edgegap expects "token <api-token>" in the Authorization header.
  const raw = env("EDGEGAP_API_TOKEN");
  const value = raw.toLowerCase().startsWith("token ") ? raw : `token ${raw}`;
  return { authorization: value, "content-type": "application/json" };
}

// Posts a deployment and returns its request id, or "" when Edgegap refused.
// Transient refusals (rate limit, capacity, upstream fault) are retried: at a
// few thousand matches an hour a single failed POST must never be what decides
// whether a player gets a match. A 4xx other than 429 is a configuration fault
// that will fail identically next second, so it is not retried.
async function deployToEdgegap(body: Record<string, unknown>, label: string): Promise<string> {
  const backoffMs = [350, 1100, 2600];
  for (let attempt = 0; attempt < backoffMs.length; attempt++) {
    const response = await fetch(`${EDGEGAP_API}/deploy`, {
      method: "POST",
      headers: edgegapHeaders(),
      body: JSON.stringify(body),
    }).catch(() => null);
    if (response?.ok) {
      const payload = await response.json().catch(() => ({})) as Record<string, unknown>;
      const requestId = String(payload.request_id ?? "").trim();
      if (requestId) return requestId;
      console.error(label, "deploy returned no request_id");
    } else {
      const status = response?.status ?? 0;
      const detail = response ? await response.text().catch(() => "") : "network error";
      console.error(label, "deploy failed", status, detail);
      const retryable = status === 0 || status === 429 || status >= 500;
      if (!retryable) return "";
    }
    if (attempt < backoffMs.length - 1) {
      await new Promise((resolve) => setTimeout(resolve, backoffMs[attempt]));
    }
  }
  return "";
}

// Fingerprint of the configured token: enough to tell two tokens apart in an
// operational check without ever exposing the token itself.
async function tokenFingerprint(): Promise<string> {
  const raw = env("EDGEGAP_API_TOKEN");
  if (!raw) return "";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(raw));
  return Array.from(new Uint8Array(digest).slice(0, 4), (b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ---------------------------------------------------------------------------
// Shared lobbies
//
// A lobby groups everyone who queues for the same region inside a short window
// onto ONE dedicated server, so friends who press play together actually meet.
// Each player gets their own HMAC-signed join ticket; the game server verifies
// the signature with MATCH_TICKET_SECRET instead of pre-registered tickets.
// ---------------------------------------------------------------------------

// Seconds a lobby stays open for more humans before the match starts with bots
// filling the rest.
function lobbyWindowSeconds(): number {
  const configured = Number.parseInt(env("GAME_LOBBY_WINDOW_SECONDS"), 10);
  if (!Number.isInteger(configured)) return 20;
  return Math.min(Math.max(configured, 5), 120);
}

function supabaseBase(): string {
  return (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
}

function serviceHeaders(): HeadersInit {
  const key = env("SUPABASE_SERVICE_ROLE_KEY");
  return {
    apikey: key,
    authorization: `Bearer ${key}`,
    "content-type": "application/json",
  };
}

function lobbiesEnabled(): boolean {
  return Boolean(supabaseBase() && env("SUPABASE_SERVICE_ROLE_KEY"));
}

async function rpc(name: string, args: Record<string, unknown>): Promise<unknown> {
  const response = await fetch(`${supabaseBase()}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: serviceHeaders(),
    body: JSON.stringify(args),
  }).catch(() => null);
  if (!response?.ok) {
    if (response) console.error("rpc failed", name, response.status, await response.text().catch(() => ""));
    return null;
  }
  return await response.json().catch(() => null);
}

// Returns whether the write actually landed. It used to swallow every failure,
// which is harmless for the endpoint cache and the status flip — both are
// retried by the next poll — but not for the write that records which
// deployment a lobby belongs to. See the call site after deployServer.
async function patchLobby(
  id: string,
  patch: Record<string, unknown>,
  attempts = 1,
): Promise<boolean> {
  for (let attempt = 0; attempt < attempts; attempt++) {
    const response = await fetch(
      `${supabaseBase()}/rest/v1/match_lobbies?id=eq.${encodeURIComponent(id)}`,
      {
        method: "PATCH",
        headers: { ...serviceHeaders(), prefer: "return=minimal" },
        body: JSON.stringify(patch),
      },
    ).catch(() => null);
    if (response?.ok) return true;
    if (response) {
      console.error(
        "patchLobby failed",
        id,
        response.status,
        await response.text().catch(() => ""),
      );
    }
    if (attempt + 1 < attempts) {
      await new Promise((resolve) => setTimeout(resolve, 250 * (attempt + 1)));
    }
  }
  return false;
}

// Is this deployment still running? Used before a player is put into a lobby
// that already has a server: the lobby row survives its container, so carrying
// a request_id is not proof that anything is listening on the other end.
// A network blip or a non-404 fault is treated as "still live" — throwing away
// a good lobby on a transient error would split the very players it holds.
async function deploymentIsLive(requestId: string): Promise<boolean> {
  const response = await fetch(`${EDGEGAP_API}/status/${encodeURIComponent(requestId)}`, {
    headers: edgegapHeaders(),
  }).catch(() => null);
  if (!response) return true;
  if (response.status === 404) return false;
  if (!response.ok) return true;
  const payload = await response.json().catch(() => ({})) as Record<string, unknown>;
  return !ERRORLIKE.has(String(payload.current_status ?? ""));
}

async function lobbyByRequestId(requestId: string): Promise<Record<string, unknown> | null> {
  const url = `${supabaseBase()}/rest/v1/match_lobbies` +
    `?request_id=eq.${encodeURIComponent(requestId)}&order=created_at.desc&limit=1`;
  const response = await fetch(url, { headers: serviceHeaders() }).catch(() => null);
  if (!response?.ok) return null;
  const rows = await response.json().catch(() => []) as Record<string, unknown>[];
  return Array.isArray(rows) && rows.length ? rows[0] : null;
}

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

// The shared ticket secret. Derived from the service role key so no extra secret
// has to be provisioned; it never leaves the function except as a server env var.
async function ticketSecret(): Promise<string> {
  const explicit = env("MATCH_TICKET_SECRET");
  if (explicit) return explicit;
  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceKey) return "";
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(serviceKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode("colony-match-ticket-v1"),
  );
  return base64(new Uint8Array(signature));
}

// "<payloadB64>.<sigB64>" with payload {u: player, e: expiry_ms, n: name} —
// the exact shape game_transport._validate_signed_join_ticket() verifies.
async function mintJoinTicket(
  secret: string,
  playerId: string,
  name: string,
  ttlMs: number,
): Promise<string> {
  const payload = JSON.stringify({
    u: playerId,
    e: Date.now() + ttlMs,
    n: name,
  });
  const payloadB64 = base64(new TextEncoder().encode(payload));
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(payloadB64),
  );
  return `${payloadB64}.${base64(new Uint8Array(signature))}`;
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

// The lobby a player is pooled into follows only their *explicit* region pick.
//
// This used to fall back to region_preference, which is the client's own ping
// probe result. Two players sitting in the same room, both showing "Otomatik",
// could measure different nearest continents (or one probe could fail and
// report nothing) and be silently sent to two different lobbies. Nobody could
// see why. Leaving the picker alone now means one shared "auto" pool, and
// placement is still good: with no coordinates Edgegap puts the server on the
// edge nearest the joining player's own IP, which beats a continent centroid.
function requestedRegion(payload: Record<string, unknown>): string {
  const selected = normalizeRegionId(payload.selected_region_id);
  if (selected !== "auto" && REGION_TARGETS[selected]) return selected;
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

// Absolute server lifetime cap (minutes). The game server self-terminates at
// this age no matter what, so a hung or runaway container can never keep billing.
function gameMaxMatchMinutes(): number {
  const configured = Number.parseInt(env("GAME_MAX_MATCH_MINUTES"), 10);
  if (!Number.isInteger(configured)) return 15;
  return Math.min(Math.max(configured, 5), 180);
}

// POST /join — deploy a server near the player and return a request handle.
async function lobbyById(id: string): Promise<Record<string, unknown> | null> {
  const url = `${supabaseBase()}/rest/v1/match_lobbies?id=eq.${encodeURIComponent(id)}&limit=1`;
  const response = await fetch(url, { headers: serviceHeaders() }).catch(() => null);
  if (!response?.ok) return null;
  const rows = await response.json().catch(() => []) as Record<string, unknown>[];
  return Array.isArray(rows) && rows.length ? rows[0] : null;
}

// Exactly one joiner may deploy the lobby's server. PostgREST only returns rows
// it actually updated, so the conditional PATCH is an atomic compare-and-set.
async function claimDeploy(lobbyId: string, playerId: string): Promise<boolean> {
  const url = `${supabaseBase()}/rest/v1/match_lobbies` +
    `?id=eq.${encodeURIComponent(lobbyId)}&deploy_claim=is.null`;
  const response = await fetch(url, {
    method: "PATCH",
    headers: { ...serviceHeaders(), prefer: "return=representation" },
    body: JSON.stringify({ deploy_claim: playerId }),
  }).catch(() => null);
  if (!response?.ok) return false;
  const rows = await response.json().catch(() => []) as unknown[];
  return Array.isArray(rows) && rows.length > 0;
}

async function deployServer(options: {
  appName: string;
  versionName: string;
  ip: string;
  regionId: string;
  regionTarget: { latitude: number; longitude: number } | undefined;
  matchId: string;
  serverId: string;
  buildId: string;
  maxPlayers: number;
  ticketSecret: string;
}): Promise<string> {
  const body: Record<string, unknown> = {
    app_name: options.appName,
    version_name: options.versionName,
    ip_list: [options.ip],
    skip_telemetry: true,
    tags: ["colony", `region-${options.regionId}`],
    env_vars: [
      { key: "MATCH_ID", value: options.matchId },
      { key: "SERVER_ID", value: options.serverId },
      { key: "BUILD_ID", value: options.buildId },
      { key: "MAX_PLAYERS", value: String(options.maxPlayers) },
      // Humans are admitted by signed ticket, so reserve every slot for people
      // and let the server convert the unclaimed ones to bots when it starts.
      { key: "EXPECTED_PLAYERS", value: String(options.maxPlayers) },
      { key: "HUMAN_PLAYER_COUNT", value: String(options.maxPlayers) },
      { key: "BOT_COUNT", value: "0" },
      { key: "RANKED_MATCH", value: "0" },
      { key: "MAX_MATCH_MINUTES", value: String(gameMaxMatchMinutes()) },
      { key: "NETWORK_TRANSPORT", value: "enet" },
      { key: "GAME_PORT", value: "20000" },
      { key: "MATCH_TICKET_SECRET", value: options.ticketSecret, is_hidden: true },
    ],
  };
  if (options.regionTarget) {
    body.location = {
      latitude: options.regionTarget.latitude,
      longitude: options.regionTarget.longitude,
    };
  }
  return await deployToEdgegap(body, "lobby");
}

// Returns a shared-lobby response. A lobby-layer failure is fail-closed: the
// caller receives a retryable 503 rather than a private one-player deployment.
async function joinSharedLobby(
  playerId: string,
  displayNameValue: string,
  regionId: string,
  regionTarget: { latitude: number; longitude: number } | undefined,
  ip: string,
  appName: string,
  versionName: string,
  buildId: string,
  maxPlayers: number,
  secret: string,
): Promise<Response> {
  // Two attempts: a lobby row outlives its server, so if the one we are handed
  // turns out to point at a deployment that has already gone, we close it and
  // claim again — which now yields a live lobby or a fresh one.
  for (let claimAttempt = 0; claimAttempt < 2; claimAttempt++) {
    const response = await claimLobbyOnce(
      playerId,
      displayNameValue,
      regionId,
      regionTarget,
      ip,
      appName,
      versionName,
      buildId,
      maxPlayers,
      secret,
    );
    if (response !== "retry") {
      return response ?? json({ ok: false, error: "matchmaking_unavailable" }, 503);
    }
  }
  return json({ ok: false, error: "matchmaking_unavailable" }, 503);
}

// One pass at the lobby claim. Returns "retry" when the claimed lobby turned
// out to be dead and was closed, so the caller should claim again.
async function claimLobbyOnce(
  playerId: string,
  displayNameValue: string,
  regionId: string,
  regionTarget: { latitude: number; longitude: number } | undefined,
  ip: string,
  appName: string,
  versionName: string,
  buildId: string,
  maxPlayers: number,
  secret: string,
): Promise<Response | null | "retry"> {
  const claimed = await rpc("claim_match_lobby", {
    p_region: regionId,
    p_player: playerId,
    p_name: displayNameValue,
    p_target: maxPlayers,
    p_window_seconds: lobbyWindowSeconds(),
    p_build: buildId,
  });
  const lobby = (Array.isArray(claimed) ? claimed[0] : claimed) as Record<string, unknown> | null;
  if (!lobby?.id) return null;

  const lobbyId = String(lobby.id);
  let requestId = String(lobby.request_id ?? "").trim();
  let matchId = String(lobby.match_id ?? "").trim();
  let serverId = String(lobby.server_id ?? "").trim();

  // A lobby that already carries a deployment is only worth joining while that
  // deployment is actually up. The container self-terminates when its match
  // ends, and nothing tells the database — so ask Edgegap.
  // A lobby created moments ago cannot have outlived its container, so the
  // liveness call is skipped for the common case. Without this guard every
  // join into a busy lobby costs an Edgegap request.
  const lobbyAgeMs = Date.now() - (Date.parse(String(lobby.created_at ?? "")) || Date.now());
  const worthChecking = lobbyAgeMs > 45_000;
  if (requestId && worthChecking && !await deploymentIsLive(requestId)) {
    // Drop this player's membership first, then retire the lobby for everyone
    // else too — the server behind it is gone, so nobody should be sent there.
    await rpc("leave_match_lobby", { p_player: playerId });
    await patchLobby(lobbyId, { status: "closed", closed_at: new Date().toISOString() });
    return "retry";
  }

  if (!requestId && await claimDeploy(lobbyId, playerId)) {
    matchId = crypto.randomUUID();
    serverId = crypto.randomUUID();
    requestId = await deployServer({
      appName,
      versionName,
      ip,
      regionId,
      regionTarget,
      matchId,
      serverId,
      buildId,
      maxPlayers,
      ticketSecret: secret,
    });
    if (!requestId) {
      // Hand the claim back rather than closing the lobby. Closing it threw away
      // everyone else already queued in this window; releasing lets the next
      // player retry the deploy and still land in the same match.
      await patchLobby(lobbyId, { deploy_claim: null });
      return json({ ok: false, error: "deploy_failed" }, 502);
    }
    // This is the write everyone else in the lobby is waiting for. Losing it
    // silently means the server is up and running with only its deployer on
    // board, while every other player in the lobby waits out the loop below and
    // is told matchmaking is unavailable — the friends this lobby exists to
    // keep together get split, and the deployer never sees a problem.
    const recorded = await patchLobby(lobbyId, {
      request_id: requestId,
      match_id: matchId,
      server_id: serverId,
    }, 3);
    if (!recorded) {
      // Hand the claim back and send everyone, this player included, around
      // again: a retry lands the whole lobby on one healthy server. The
      // deployment just made is orphaned, and shuts itself down on its own
      // "no authenticated player joined" watchdog, so nothing keeps billing.
      await patchLobby(lobbyId, { deploy_claim: null }, 3);
      return json({ ok: false, error: "matchmaking_unavailable" }, 503);
    }
  }

  // Someone else is deploying for this lobby: wait for the identity to land.
  // The budget has to outlast the claim holder's deploy retries, otherwise a
  // retried deploy pushes this player onto the solo path — splitting up exactly
  // the friends the lobby exists to keep together.
  for (let attempt = 0; attempt < 20 && !requestId; attempt++) {
    await new Promise((resolve) => setTimeout(resolve, 700));
    const row = await lobbyById(lobbyId);
    if (!row) break;
    if (String(row.status ?? "") === "closed") return null;
    requestId = String(row.request_id ?? "").trim();
    matchId = String(row.match_id ?? "").trim();
    serverId = String(row.server_id ?? "").trim();
  }
  if (!requestId || !matchId || !serverId) {
    // This player has a lobby; only its server is not up yet. Falling back to a
    // private match here would guarantee a split, so ask the client to retry —
    // the next attempt lands on this same lobby with its server attached.
    return json({ ok: false, error: "matchmaking_unavailable" }, 503);
  }

  const joinTicket = await mintJoinTicket(secret, playerId, displayNameValue, 10 * 60 * 1000);
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

  const maxPlayers = gameMaxPlayers();
  const buildId = env("GAME_BUILD_ID") || "colony";

  // The only production path: put everyone queueing for this region into a
  // shared lobby. Never degrade to one server per player. If the database/RPC
  // boundary is unhealthy, returning a retryable error preserves matchmaking
  // correctness and prevents an unbounded deployment/cost fan-out.
  const secret = await ticketSecret();
  if (!lobbiesEnabled() || !secret) {
    console.error("shared matchmaking unavailable: lobby credentials are missing");
    return json({ ok: false, error: "matchmaking_unavailable" }, 503);
  }
  return await joinSharedLobby(
    authenticatedPlayerId,
    trustedDisplayName,
    regionId,
    regionTarget,
    ip,
    appName,
    versionName,
    buildId,
    maxPlayers,
    secret,
  );
}

// GET /status/{request_id} — poll Edgegap; when READY return the direct ip:port.
async function status(requestId: string): Promise<Response> {
  if (!/^[A-Za-z0-9_-]{4,128}$/.test(requestId)) {
    return json({ ok: false, error: "invalid_request_id" }, 400);
  }

  // Hold everyone in the queue while the lobby is still collecting humans, so
  // players who queued together are released into the match together. Once the
  // window closes (or the lobby fills) the server converts the unclaimed slots
  // to bots.
  let humansInLobby = 1;
  let lobbyId = "";
  let lobbyRegionId = "";
  if (lobbiesEnabled()) {
    const lobby = await lobbyByRequestId(requestId);
    if (lobby?.id) {
      lobbyId = String(lobby.id);
      lobbyRegionId = String(lobby.region_id ?? "");
      humansInLobby = Math.max(Number(lobby.human_count ?? 1), 1);
      // No queue hold. The countdown used to keep everyone waiting for the fill
      // window to expire before they were allowed into their own match, which
      // bought nothing: what puts two players together is sharing a lobby, not
      // being released at the same instant. Since a match already running can be
      // joined, holding people back only delayed the first player and made the
      // wait look like the reason they ended up apart.
      //
      // So a player enters as soon as the server is up, and the lobby keeps
      // accepting real players into that same match until it is full — each one
      // taking a slot the bot backfill would otherwise have used. When it fills,
      // the next player opens the next match.
      if (String(lobby.status ?? "") === "filling") {
        await patchLobby(lobbyId, { status: "ready" });
      }

      // Serve the endpoint from the lobby row once it is known.
      //
      // Every player polls this route once a second while they wait, and each
      // poll used to call Edgegap. A ten-player lobby waiting forty seconds for
      // its container therefore sent ~400 identical status requests for a
      // single match, all asking about the same deployment. That is the first
      // thing that falls over as the game grows: Edgegap rate-limits long
      // before the game server does.
      //
      // The lobby table has carried host/port columns since it was created and
      // nothing ever wrote them. Now the first poll to see READY stores the
      // endpoint, and everyone else is answered from Postgres.
      const cachedHost = String(lobby.host ?? "").trim();
      const cachedPort = Number(lobby.port ?? 0);
      if (cachedHost && Number.isInteger(cachedPort) && cachedPort > 0) {
        return readyResponse(requestId, cachedHost, cachedPort, lobbyRegionId, humansInLobby);
      }
    }
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
  // First poll to see a live endpoint publishes it, so nobody else in this
  // lobby has to ask Edgegap again.
  if (lobbyId) {
    await patchLobby(lobbyId, { host: publicIp, port: externalPort });
  }
  const humanPlayers = Math.min(Math.max(humansInLobby, 1), gameMaxPlayers());
  return json({
    ok: true,
    ready: true,
    human_players: humanPlayers,
    bot_players: Math.max(gameMaxPlayers() - humanPlayers, 0),
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

// The cached form of the ready response. The city/country Edgegap reports are
// not stored, so the label falls back to the region the lobby asked for — the
// endpoint itself, which is what the client connects to, is exact.
function readyResponse(
  requestId: string,
  host: string,
  port: number,
  regionId: string,
  humansInLobby: number,
): Response {
  const regionTarget = REGION_TARGETS[regionId];
  const humanPlayers = Math.min(Math.max(humansInLobby, 1), gameMaxPlayers());
  return json({
    ok: true,
    ready: true,
    human_players: humanPlayers,
    bot_players: Math.max(gameMaxPlayers() - humanPlayers, 0),
    assignment: {
      transport: "enet",
      host,
      port,
      request_id: requestId,
      region_id: regionId,
      region_name: regionTarget?.displayName ?? "Edgegap — En Yakın",
      region_short_name: regionTarget?.shortName ?? "EDGE",
    },
  });
}

// DELETE /cancel/{request_id} — the player backed out of the queue.
async function cancel(requestId: string, request: Request): Promise<Response> {
  if (!/^[A-Za-z0-9_-]{4,128}$/.test(requestId)) {
    return json({ ok: false, error: "invalid_request_id" }, 400);
  }
  // In a shared lobby only the last player out turns off the lights — cancelling
  // must never tear down a server the other players are still waiting on.
  if (lobbiesEnabled()) {
    const playerId = await authenticatedUserId(request);
    if (playerId) {
      const left = await rpc("leave_match_lobby", { p_player: playerId });
      const row = (Array.isArray(left) ? left[0] : left) as Record<string, unknown> | null;
      if (row?.id && Number(row.human_count ?? 0) > 0) {
        return json({ ok: true, kept_running: true });
      }
    }
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
      // "configured" only proves the secrets are non-empty. `?verify=1` also
      // asks Edgegap whether the stored token is actually accepted, which is
      // the difference between a working deploy path and a silent 401 that only
      // shows up as a failed match. The fingerprint identifies *which* token is
      // stored without revealing it.
      const body: Record<string, unknown> = {
        ok: true,
        service: "colony-edgegap-matchmaking",
        configured: Boolean(env("EDGEGAP_API_TOKEN") && env("EDGEGAP_APP_NAME")),
        matchmaking_mode: "shared_only",
        private_match_fallback: false,
      };
      if (new URL(request.url).searchParams.get("verify") === "1") {
        const probe = await fetch(`${EDGEGAP_API}/apps`, { headers: edgegapHeaders() })
          .catch(() => null);
        body.edgegap_status = probe?.status ?? 0;
        body.edgegap_ok = Boolean(probe?.ok);
        body.token_fingerprint = await tokenFingerprint();
        body.app_name = env("EDGEGAP_APP_NAME");
        body.app_version = env("EDGEGAP_APP_VERSION");
        // Whether players are being pooled at all. If lobbies are off — no
        // service-role key, no ticket secret, or the table is unreachable —
        // every /join silently falls through to a private one-player server,
        // which looks exactly like "we keep landing in different matches" and
        // is invisible from outside.
        body.lobbies_enabled = lobbiesEnabled();
        body.ticket_secret = Boolean(await ticketSecret());
        body.service_role_key = Boolean(env("SUPABASE_SERVICE_ROLE_KEY"));
        body.lobby_window_seconds = lobbyWindowSeconds();
        if (lobbiesEnabled()) {
          const url = `${supabaseBase()}/rest/v1/match_lobbies` +
            `?select=region_id,build_id,status,human_count,target_humans,request_id,created_at` +
            `&order=created_at.desc&limit=6`;
          const rows = await fetch(url, { headers: serviceHeaders() }).catch(() => null);
          body.lobby_table_status = rows?.status ?? 0;
          // Does the service role actually have EXECUTE on the lobby functions?
          // leave_match_lobby for an unknown player is a no-op, so this asks the
          // question without creating anything.
          const rpcProbe = await fetch(`${supabaseBase()}/rest/v1/rpc/leave_match_lobby`, {
            method: "POST",
            headers: serviceHeaders(),
            body: JSON.stringify({ p_player: "00000000-0000-0000-0000-000000000000" }),
          }).catch(() => null);
          body.lobby_rpc_status = rpcProbe?.status ?? 0;
          if (rows?.ok) {
            const list = await rows.json().catch(() => []) as Record<string, unknown>[];
            // Identifiers are deliberately left out; this is a shape report, not
            // a way to look up somebody's match.
            body.recent_lobbies = list.map((row) => ({
              region: String(row.region_id ?? ""),
              build: String(row.build_id ?? ""),
              status: String(row.status ?? ""),
              humans: Number(row.human_count ?? 0),
              target: Number(row.target_humans ?? 0),
              has_server: Boolean(String(row.request_id ?? "").trim()),
              age_seconds: Math.round(
                (Date.now() - (Date.parse(String(row.created_at ?? "")) || Date.now())) / 1000,
              ),
            }));
          }
        }
      }
      return json(body);
    }
    if (request.method === "POST" && action === "join") return await join(request);
    if (request.method === "GET" && action === "status") return await status(requestId);
    if (request.method === "DELETE" && action === "cancel") {
      return await cancel(requestId, request);
    }
    return json({ ok: false, error: "not_found" }, 404);
  } catch (error) {
    console.error("matchmaking error", error instanceof Error ? error.message : String(error));
    return json({ ok: false, error: "matchmaking_unavailable" }, 503);
  }
});
