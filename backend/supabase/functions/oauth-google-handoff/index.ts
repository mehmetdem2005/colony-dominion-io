const JSON_HEADERS = new Headers({
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store, no-cache, must-revalidate, private, max-age=0",
  Pragma: "no-cache",
  Expires: "0",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
});

const REQUEST_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HASH_PATTERN = /^[0-9a-f]{64}$/;
const CALLBACK_NONCE_PATTERN = /^[0-9a-f]{64}$/;
const PKCE_CHALLENGE_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const AUTH_CODE_PATTERN = /^[A-Za-z0-9._~-]{8,2048}$/;
const HANDOFF_TTL_SECONDS = 300;
const TABLE = "oauth_handoffs";
const FUNCTION_PATH = "/functions/v1/oauth-google-handoff";
const UTF8_ENCODER = new TextEncoder();
const SAFE_CALLBACK_ERRORS = new Map<string, string>([
  ["access_denied", "google_oauth_cancelled"],
  ["temporarily_unavailable", "google_oauth_unavailable"],
  ["server_error", "google_oauth_failed"],
  ["invalid_request", "google_oauth_failed"],
]);

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: JSON_HEADERS });
}

function randomHex(byteCount: number): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(byteCount)), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

function randomNonce(): string {
  return randomHex(16);
}

function html(htmlSource: string, nonce: string, status = 200): Response {
  const headers = new Headers({
    "Content-Type": "text/html; charset=utf-8",
    "Content-Disposition": "inline",
    "Cache-Control": "no-store, no-cache, must-revalidate, private, max-age=0",
    Pragma: "no-cache",
    Expires: "0",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Resource-Policy": "same-origin",
    "Permissions-Policy":
      "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
    "Content-Security-Policy":
      `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; connect-src 'none'; img-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
  });
  return new Response(UTF8_ENCODER.encode(htmlSource), { status, headers });
}

function callbackPage(ok: boolean, reason: string, status = 200): Response {
  const nonce = randomNonce();
  const safeReason = reason === "cancelled"
    ? "Google girişi iptal edildi."
    : reason === "expired"
    ? "Giriş bağlantısının süresi doldu. Uygulamadan yeniden başlat."
    : reason === "invalid"
    ? "Giriş bağlantısı doğrulanamadı. Uygulamadan yeniden başlat."
    : ok
    ? "Kimlik doğrulama tamamlandı. Colony Dominion.io uygulamasına geri dön."
    : "Google girişi tamamlanamadı. Uygulamadan yeniden dene.";
  const title = ok ? "Google girişi doğrulandı" : "Google girişi tamamlanamadı";
  const mark = ok ? "✓" : "!";
  const detailClass = ok ? "detail" : "detail error";
  const autoClose = ok
    ? `<script nonce="${nonce}">history.replaceState(null, document.title, location.pathname);setTimeout(() => window.close(), 900);</script>`
    : `<script nonce="${nonce}">history.replaceState(null, document.title, location.pathname);</script>`;
  const source = `<!doctype html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="referrer" content="no-referrer">
<title>Colony Dominion.io — Google Girişi</title>
<style>
:root{color-scheme:dark;font-family:Inter,system-ui,-apple-system,sans-serif;background:#07110d;color:#eef7f1}*{box-sizing:border-box}body{min-height:100vh;margin:0;display:grid;place-items:center;padding:24px;background:radial-gradient(circle at 50% 0,#143d2b 0,#07110d 52%,#030805 100%)}main{width:min(520px,100%);padding:34px;border:1px solid #315d47;border-radius:24px;background:rgba(8,22,15,.96);box-shadow:0 28px 80px rgba(0,0,0,.45);text-align:center}.mark{width:58px;height:58px;margin:0 auto 18px;border-radius:18px;display:grid;place-items:center;background:#c8f56a;color:#0a160e;font-weight:900;font-size:30px}.mark.error{background:#ffd3d3;color:#3a1717}h1{font-size:27px;margin:0 0 12px}p{line-height:1.55;color:#b8cabe;margin:0}.detail{margin-top:18px;padding:14px;border-radius:14px;background:#0d2a1b;color:#d9ebe0;font-size:14px}.detail.error{background:#3a1717;color:#ffd8d8}</style>
</head>
<body><main><div class="mark${ok ? "" : " error"}">${mark}</div><h1>${title}</h1><p>Bu sayfa hiçbir oturum anahtarı içermez.</p><div class="${detailClass}">${safeReason}</div></main>${autoClose}</body>
</html>`;
  return html(source, nonce, status);
}

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)?.trim() ?? "";
  if (!value) throw new Error(`${name} is not configured`);
  return value.replace(/\/$/, "");
}

function supabaseUrl(): string {
  return requiredEnvironment("SUPABASE_URL");
}

function functionBaseUrl(): string {
  return `${supabaseUrl()}${FUNCTION_PATH}`;
}

function serviceHeaders(): HeadersInit {
  const serviceKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
  return {
    apikey: serviceKey,
    authorization: `Bearer ${serviceKey}`,
    "content-type": "application/json",
  };
}

function routeParts(request: Request): string[] {
  const path = new URL(request.url).pathname;
  const marker = "/oauth-google-handoff";
  const index = path.indexOf(marker);
  if (index < 0) return [];
  return path
    .slice(index + marker.length)
    .split("/")
    .map((part) => part.trim())
    .filter(Boolean);
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(length) && length > 12_000) {
    throw new Error("Request body is too large");
  }
  const parsed = await request.json().catch(() => null);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Request body must be a JSON object");
  }
  return parsed as Record<string, unknown>;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", UTF8_ENCODER.encode(value));
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

async function deleteExpired(): Promise<void> {
  await fetch(
    `${supabaseUrl()}/rest/v1/${TABLE}?expires_at=lt.${encodeURIComponent(new Date().toISOString())}`,
    { method: "DELETE", headers: serviceHeaders() },
  );
}

async function begin(request: Request): Promise<Response> {
  const body = await readJson(request);
  const requestId = String(body.request_id ?? "").trim();
  const secretHash = String(body.secret_hash ?? "").trim().toLowerCase();
  const codeChallenge = String(body.code_challenge ?? "").trim();
  if (
    !REQUEST_ID_PATTERN.test(requestId) ||
    !HASH_PATTERN.test(secretHash) ||
    !PKCE_CHALLENGE_PATTERN.test(codeChallenge)
  ) {
    return json({ ok: false, error: "invalid_pkce_handoff_request" }, 400);
  }

  await deleteExpired();
  const callbackNonce = randomHex(32);
  const callbackNonceHash = await sha256Hex(callbackNonce);
  const expiresAt = new Date(Date.now() + HANDOFF_TTL_SECONDS * 1000).toISOString();
  const insert = await fetch(`${supabaseUrl()}/rest/v1/${TABLE}`, {
    method: "POST",
    headers: { ...serviceHeaders(), prefer: "return=minimal" },
    body: JSON.stringify({
      request_id: requestId,
      secret_hash: secretHash,
      flow_type: "pkce",
      callback_nonce_hash: callbackNonceHash,
      auth_code: null,
      refresh_token: null,
      error_message: null,
      created_at: new Date().toISOString(),
      expires_at: expiresAt,
      completed_at: null,
      consumed_at: null,
    }),
  });
  if (!insert.ok) {
    console.error("OAuth PKCE handoff begin failed", insert.status, await insert.text());
    return json({ ok: false, error: "handoff_store_unavailable" }, 503);
  }

  const callbackUrl = `${functionBaseUrl()}/callback/${requestId}/${callbackNonce}`;
  const authorizeUrl = new URL(`${supabaseUrl()}/auth/v1/authorize`);
  authorizeUrl.searchParams.set("provider", "google");
  authorizeUrl.searchParams.set("redirect_to", callbackUrl);
  authorizeUrl.searchParams.set("scopes", "openid email profile");
  authorizeUrl.searchParams.set("flow_type", "pkce");
  authorizeUrl.searchParams.set("code_challenge", codeChallenge);
  authorizeUrl.searchParams.set("code_challenge_method", "s256");
  return json({
    ok: true,
    request_id: requestId,
    authorize_url: authorizeUrl.toString(),
    expires_at: expiresAt,
    poll_interval_ms: 1000,
    flow_type: "pkce",
  });
}

async function loadHandoff(requestId: string): Promise<Record<string, unknown> | null> {
  const response = await fetch(
    `${supabaseUrl()}/rest/v1/${TABLE}?request_id=eq.${requestId}&select=request_id,secret_hash,flow_type,callback_nonce_hash,auth_code,error_message,expires_at,completed_at,consumed_at`,
    { headers: serviceHeaders(), cache: "no-store" },
  );
  if (!response.ok) return null;
  const rows = await response.json().catch(() => []);
  return Array.isArray(rows) && rows.length === 1
    ? (rows[0] as Record<string, unknown>)
    : null;
}

async function deleteHandoff(requestId: string): Promise<void> {
  await fetch(`${supabaseUrl()}/rest/v1/${TABLE}?request_id=eq.${requestId}`, {
    method: "DELETE",
    headers: serviceHeaders(),
  });
}

async function callback(
  request: Request,
  requestId: string,
  callbackNonce: string,
): Promise<Response> {
  if (
    !REQUEST_ID_PATTERN.test(requestId) ||
    !CALLBACK_NONCE_PATTERN.test(callbackNonce)
  ) {
    return callbackPage(false, "invalid", 400);
  }
  const row = await loadHandoff(requestId);
  if (!row || String(row.flow_type ?? "") !== "pkce") {
    return callbackPage(false, "invalid", 404);
  }
  const expectedNonceHash = String(row.callback_nonce_hash ?? "");
  const suppliedNonceHash = await sha256Hex(callbackNonce);
  if (
    !HASH_PATTERN.test(expectedNonceHash) ||
    !constantTimeEqual(expectedNonceHash, suppliedNonceHash)
  ) {
    return callbackPage(false, "invalid", 403);
  }
  if (Date.parse(String(row.expires_at ?? "")) <= Date.now()) {
    await deleteHandoff(requestId);
    return callbackPage(false, "expired", 410);
  }
  if (row.completed_at || row.consumed_at) {
    return callbackPage(false, "expired", 410);
  }

  const url = new URL(request.url);
  const authCode = String(url.searchParams.get("code") ?? "").trim();
  const rawError = String(url.searchParams.get("error") ?? "").trim();
  const errorMessage = rawError
    ? (SAFE_CALLBACK_ERRORS.get(rawError) ?? "google_oauth_failed")
    : "";
  if (!AUTH_CODE_PATTERN.test(authCode) && !errorMessage) {
    return callbackPage(false, "invalid", 400);
  }

  const query = new URLSearchParams({
    request_id: `eq.${requestId}`,
    expires_at: `gt.${new Date().toISOString()}`,
    completed_at: "is.null",
    consumed_at: "is.null",
  });
  const update = await fetch(
    `${supabaseUrl()}/rest/v1/${TABLE}?${query.toString()}`,
    {
      method: "PATCH",
      headers: { ...serviceHeaders(), prefer: "return=representation" },
      body: JSON.stringify({
        auth_code: authCode || null,
        error_message: errorMessage || null,
        completed_at: new Date().toISOString(),
      }),
    },
  );
  const rows = update.ok ? await update.json().catch(() => []) : [];
  if (!update.ok || !Array.isArray(rows) || rows.length !== 1) {
    return callbackPage(false, "expired", 410);
  }
  return callbackPage(
    !errorMessage,
    errorMessage === "google_oauth_cancelled" ? "cancelled" : "failed",
    errorMessage ? 400 : 200,
  );
}

async function poll(request: Request, requestId: string): Promise<Response> {
  if (!REQUEST_ID_PATTERN.test(requestId)) {
    return json({ ok: false, error: "invalid_request_id" }, 400);
  }
  const secret = request.headers.get("x-colony-oauth-secret")?.trim() ?? "";
  if (secret.length < 32 || secret.length > 256) {
    return json({ ok: false, error: "invalid_handoff_secret" }, 401);
  }
  const row = await loadHandoff(requestId);
  if (!row) return json({ ok: false, error: "handoff_not_found" }, 404);
  if (String(row.flow_type ?? "") !== "pkce") {
    await deleteHandoff(requestId);
    return json({ ok: false, error: "unsupported_oauth_flow" }, 410);
  }
  const suppliedHash = await sha256Hex(secret);
  if (!constantTimeEqual(String(row.secret_hash ?? ""), suppliedHash)) {
    return json({ ok: false, error: "handoff_secret_mismatch" }, 403);
  }
  if (Date.parse(String(row.expires_at ?? "")) <= Date.now()) {
    await deleteHandoff(requestId);
    return json({ ok: false, error: "handoff_expired" }, 410);
  }
  const errorMessage = String(row.error_message ?? "");
  if (errorMessage) {
    await deleteHandoff(requestId);
    return json({ ok: false, error: errorMessage }, 400);
  }
  if (row.consumed_at) {
    await deleteHandoff(requestId);
    return json({ ok: false, error: "handoff_expired_or_completed" }, 410);
  }
  const authCode = String(row.auth_code ?? "");
  if (!AUTH_CODE_PATTERN.test(authCode)) {
    return json({ ok: true, ready: false, flow_type: "pkce" });
  }

  const consumeQuery = new URLSearchParams({
    request_id: `eq.${requestId}`,
    expires_at: `gt.${new Date().toISOString()}`,
    consumed_at: "is.null",
  });
  const consume = await fetch(
    `${supabaseUrl()}/rest/v1/${TABLE}?${consumeQuery.toString()}`,
    {
      method: "PATCH",
      headers: { ...serviceHeaders(), prefer: "return=representation" },
      body: JSON.stringify({
        consumed_at: new Date().toISOString(),
        auth_code: null,
        callback_nonce_hash: null,
      }),
    },
  );
  const consumedRows = consume.ok ? await consume.json().catch(() => []) : [];
  if (!consume.ok || !Array.isArray(consumedRows) || consumedRows.length !== 1) {
    return json({ ok: false, error: "handoff_expired_or_completed" }, 410);
  }
  await deleteHandoff(requestId);
  return json({ ok: true, ready: true, flow_type: "pkce", auth_code: authCode });
}

async function cancel(request: Request, requestId: string): Promise<Response> {
  if (!REQUEST_ID_PATTERN.test(requestId)) {
    return json({ ok: false, error: "invalid_request_id" }, 400);
  }
  const secret = request.headers.get("x-colony-oauth-secret")?.trim() ?? "";
  if (secret.length < 32 || secret.length > 256) {
    return json({ ok: false, error: "invalid_handoff_secret" }, 401);
  }
  const row = await loadHandoff(requestId);
  if (!row) return json({ ok: true });
  if (!constantTimeEqual(String(row.secret_hash ?? ""), await sha256Hex(secret))) {
    return json({ ok: false, error: "handoff_secret_mismatch" }, 403);
  }
  await deleteHandoff(requestId);
  return json({ ok: true });
}

Deno.serve(async (request) => {
  try {
    const parts = routeParts(request);
    const action = parts[0] ?? "health";
    const requestId = parts[1] ?? "";
    const callbackNonce = parts[2] ?? "";
    if (request.method === "GET" && action === "health") {
      return json({
        ok: true,
        service: "colony-google-oauth-handoff",
        ttl_seconds: HANDOFF_TTL_SECONDS,
        flow_type: "pkce",
        tokens_in_browser: false,
      });
    }
    if (request.method === "POST" && action === "begin") {
      return await begin(request);
    }
    if (request.method === "GET" && action === "callback") {
      return await callback(request, requestId, callbackNonce);
    }
    if (request.method === "GET" && action === "poll") {
      return await poll(request, requestId);
    }
    if (request.method === "DELETE" && action === "cancel") {
      return await cancel(request, requestId);
    }
    return json({ ok: false, error: "not_found" }, 404);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("OAuth PKCE handoff request failed", message);
    return json({ ok: false, error: "oauth_handoff_unavailable" }, 503);
  }
});
