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

function clientIp(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for") ?? "";
  const first = forwarded.split(",")[0]?.trim();
  return first || (request.headers.get("x-real-ip") ?? "").trim();
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
async function requireUser(request: Request): Promise<boolean> {
  const auth = request.headers.get("authorization") ?? "";
  if (!/^Bearer\s+.+/i.test(auth)) return false;
  const base = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!base || !anon) return false;
  const response = await fetch(`${base}/auth/v1/user`, {
    headers: { apikey: anon, authorization: auth },
  }).catch(() => null);
  return Boolean(response && response.ok);
}

// POST /join — deploy a server near the player and return a request handle.
async function join(request: Request): Promise<Response> {
  const appName = env("EDGEGAP_APP_NAME");
  const versionName = env("EDGEGAP_APP_VERSION");
  if (!env("EDGEGAP_API_TOKEN") || !appName || !versionName) {
    return json({ ok: false, error: "matchmaking_not_configured" }, 503);
  }
  if (!(await requireUser(request))) {
    return json({ ok: false, error: "authentication_required" }, 401);
  }
  const ip = clientIp(request);
  if (!ip) return json({ ok: false, error: "client_ip_unavailable" }, 400);

  const body = {
    app_name: appName,
    version_name: versionName,
    ip_list: [ip],
    env_vars: [
      { key: "BUILD_ID", value: env("GAME_BUILD_ID") || "colony" },
      { key: "MAX_PLAYERS", value: env("GAME_MAX_PLAYERS") || "10" },
      { key: "NETWORK_TRANSPORT", value: "enet" },
    ],
  };
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
  return json({ ok: true, request_id: requestId, poll_interval_ms: 1500 });
}

// GET /status/{request_id} — poll Edgegap; when READY return the direct ip:port.
async function status(requestId: string): Promise<Response> {
  if (!/^[A-Za-z0-9_-]{4,128}$/.test(requestId)) {
    return json({ ok: false, error: "invalid_request_id" }, 400);
  }
  const response = await fetch(`${EDGEGAP_API}/status/${encodeURIComponent(requestId)}`, {
    headers: edgegapHeaders(),
  });
  const payload = await response.json().catch(() => ({}));
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

  return json({
    ok: true,
    ready: true,
    assignment: {
      transport: "enet",
      host: publicIp,
      port: externalPort,
      request_id: requestId,
      region_name: String(payload.city ?? payload.country ?? "Edge"),
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
