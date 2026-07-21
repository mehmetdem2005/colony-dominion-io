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
const HANDOFF_TTL_SECONDS = 300;
const TABLE = "oauth_handoffs";
const FUNCTION_PATH = "/functions/v1/oauth-google-handoff";
const SAFE_OAUTH_ERRORS = new Set([
  "google_oauth_failed",
  "missing_oauth_result",
]);
const UTF8_ENCODER = new TextEncoder();

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: JSON_HEADERS });
}

function randomNonce(): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(16)), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
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
      `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; connect-src 'self'; img-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`,
  });
  return new Response(UTF8_ENCODER.encode(htmlSource), { status, headers });
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
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
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
    {
      method: "DELETE",
      headers: serviceHeaders(),
    },
  );
}

async function begin(request: Request): Promise<Response> {
  const body = await readJson(request);
  const requestId = String(body.request_id ?? "").trim();
  const secretHash = String(body.secret_hash ?? "")
    .trim()
    .toLowerCase();
  if (!REQUEST_ID_PATTERN.test(requestId) || !HASH_PATTERN.test(secretHash)) {
    return json({ ok: false, error: "invalid_handoff_request" }, 400);
  }

  await deleteExpired();
  const expiresAt = new Date(
    Date.now() + HANDOFF_TTL_SECONDS * 1000,
  ).toISOString();
  const insert = await fetch(`${supabaseUrl()}/rest/v1/${TABLE}`, {
    method: "POST",
    headers: {
      ...serviceHeaders(),
      prefer: "return=minimal",
    },
    body: JSON.stringify({
      request_id: requestId,
      secret_hash: secretHash,
      refresh_token: null,
      error_message: null,
      created_at: new Date().toISOString(),
      expires_at: expiresAt,
      completed_at: null,
      consumed_at: null,
    }),
  });
  if (!insert.ok) {
    console.error(
      "OAuth handoff begin failed",
      insert.status,
      await insert.text(),
    );
    return json({ ok: false, error: "handoff_store_unavailable" }, 503);
  }

  const callbackUrl = `${functionBaseUrl()}/callback/${requestId}`;
  const authorizeUrl = new URL(`${supabaseUrl()}/auth/v1/authorize`);
  authorizeUrl.searchParams.set("provider", "google");
  authorizeUrl.searchParams.set("redirect_to", callbackUrl);
  authorizeUrl.searchParams.set("scopes", "openid email profile");
  return json({
    ok: true,
    request_id: requestId,
    authorize_url: authorizeUrl.toString(),
    expires_at: expiresAt,
    poll_interval_ms: 1000,
  });
}

function callbackPage(requestId: string): Response {
  const completeUrl = `${functionBaseUrl()}/complete/${requestId}`;
  const escapedCompleteUrl = JSON.stringify(completeUrl);
  const nonce = randomNonce();
  const htmlSource = `<!doctype html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="referrer" content="no-referrer">
<title>Colony Dominion.io — Google Girişi</title>
<style>
:root{color-scheme:dark;font-family:Inter,system-ui,-apple-system,sans-serif;background:#07110d;color:#eef7f1}*{box-sizing:border-box}body{min-height:100vh;margin:0;display:grid;place-items:center;padding:24px;background:radial-gradient(circle at 50% 0,#143d2b 0,#07110d 52%,#030805 100%)}main{width:min(520px,100%);padding:34px;border:1px solid #315d47;border-radius:24px;background:rgba(8,22,15,.96);box-shadow:0 28px 80px rgba(0,0,0,.45);text-align:center}.mark{width:58px;height:58px;margin:0 auto 18px;border-radius:18px;display:grid;place-items:center;background:#c8f56a;color:#0a160e;font-weight:900;font-size:30px}h1{font-size:27px;margin:0 0 12px}p{line-height:1.55;color:#b8cabe;margin:0}.detail{margin-top:18px;padding:14px;border-radius:14px;background:#0d2a1b;color:#d9ebe0;font-size:14px}.error{background:#3a1717;color:#ffd8d8}</style>
</head>
<body><main><div class="mark" id="mark">…</div><h1 id="title">Google girişi tamamlanıyor</h1><p id="message">Güvenli oturum oyuna aktarılıyor. Bu sekmeyi kapatma.</p><div class="detail" id="detail">Bağlantı doğrulanıyor…</div></main>
<script nonce="${nonce}">
(() => {
  const completeUrl = ${escapedCompleteUrl};
  const fragment = location.hash;
  history.replaceState(null, document.title, location.pathname + location.search);
  const params = new URLSearchParams(fragment.replace(/^#/, ""));
  const refreshToken = params.get("refresh_token") || "";
  const oauthFailed = params.has("error_description") || params.has("error");
  const title = document.getElementById("title");
  const message = document.getElementById("message");
  const detail = document.getElementById("detail");
  const mark = document.getElementById("mark");
  const finish = (ok, text) => {
    mark.textContent = ok ? "✓" : "!";
    title.textContent = ok ? "Google girişi tamamlandı" : "Google girişi tamamlanamadı";
    message.textContent = ok ? "Colony Dominion.io uygulamasına geri dönebilirsin." : "Uygulamaya dönüp yeniden dene.";
    detail.textContent = text;
    if (!ok) detail.classList.add("error");
    if (ok) setTimeout(() => window.close(), 900);
  };
  const payload = refreshToken
    ? { refresh_token: refreshToken }
    : { error: oauthFailed ? "google_oauth_failed" : "missing_oauth_result" };
  fetch(completeUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
    cache: "no-store",
    credentials: "omit",
    referrerPolicy: "no-referrer",
  }).then(async (response) => {
    if (!response.ok) throw new Error("Oturum aktarımı reddedildi");
    finish(Boolean(refreshToken), refreshToken ? "Oturum oyuna güvenli biçimde aktarıldı." : "Google oturumu tamamlanamadı.");
  }).catch(() => finish(false, "Güvenli aktarım servisine ulaşılamadı."));
})();
</script></body></html>`;
  return html(htmlSource, nonce);
}

async function complete(
  request: Request,
  requestId: string,
): Promise<Response> {
  if (!REQUEST_ID_PATTERN.test(requestId)) {
    return json({ ok: false, error: "invalid_request_id" }, 400);
  }
  const body = await readJson(request);
  const refreshToken = String(body.refresh_token ?? "").trim();
  const rawError = String(body.error ?? "").trim();
  const errorMessage = rawError
    ? SAFE_OAUTH_ERRORS.has(rawError)
      ? rawError
      : "google_oauth_failed"
    : "";
  if (!refreshToken && !errorMessage) {
    return json({ ok: false, error: "missing_oauth_result" }, 400);
  }
  if (
    refreshToken &&
    (refreshToken.length < 16 || refreshToken.length > 4096)
  ) {
    return json({ ok: false, error: "invalid_refresh_token" }, 400);
  }

  const query = new URLSearchParams({
    request_id: `eq.${requestId}`,
    expires_at: `gt.${new Date().toISOString()}`,
    completed_at: "is.null",
  });
  const update = await fetch(
    `${supabaseUrl()}/rest/v1/${TABLE}?${query.toString()}`,
    {
      method: "PATCH",
      headers: { ...serviceHeaders(), prefer: "return=representation" },
      body: JSON.stringify({
        refresh_token: refreshToken || null,
        error_message: errorMessage || null,
        completed_at: new Date().toISOString(),
      }),
    },
  );
  const rows = update.ok ? await update.json().catch(() => []) : [];
  if (!update.ok || !Array.isArray(rows) || rows.length !== 1) {
    return json({ ok: false, error: "handoff_expired_or_completed" }, 410);
  }
  return json({ ok: true });
}

async function loadHandoff(
  requestId: string,
): Promise<Record<string, unknown> | null> {
  const response = await fetch(
    `${supabaseUrl()}/rest/v1/${TABLE}?request_id=eq.${requestId}&select=request_id,secret_hash,refresh_token,error_message,expires_at,completed_at,consumed_at`,
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
  const refreshToken = String(row.refresh_token ?? "");
  if (!refreshToken) return json({ ok: true, ready: false });

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
        refresh_token: null,
      }),
    },
  );
  const consumedRows = consume.ok ? await consume.json().catch(() => []) : [];
  if (
    !consume.ok ||
    !Array.isArray(consumedRows) ||
    consumedRows.length !== 1
  ) {
    return json({ ok: false, error: "handoff_expired_or_completed" }, 410);
  }
  await deleteHandoff(requestId);
  return json({ ok: true, ready: true, refresh_token: refreshToken });
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
  if (
    !constantTimeEqual(String(row.secret_hash ?? ""), await sha256Hex(secret))
  ) {
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
    if (request.method === "GET" && action === "health") {
      return json({
        ok: true,
        service: "colony-google-oauth-handoff",
        ttl_seconds: HANDOFF_TTL_SECONDS,
      });
    }
    if (request.method === "POST" && action === "begin") {
      return await begin(request);
    }
    if (request.method === "GET" && action === "callback") {
      if (!REQUEST_ID_PATTERN.test(requestId)) {
        return json({ ok: false, error: "invalid_request_id" }, 400);
      }
      return callbackPage(requestId);
    }
    if (request.method === "POST" && action === "complete") {
      return await complete(request, requestId);
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
    console.error("OAuth handoff request failed", message);
    return json({ ok: false, error: "oauth_handoff_unavailable" }, 503);
  }
});
