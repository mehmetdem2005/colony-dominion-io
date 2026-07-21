import { actor } from "rivetkit";

const port = Number(process.env.RIVET_PORT ?? process.env.PORT ?? 3000);
const internalBaseUrl = (process.env.INTERNAL_BASE_URL ?? `http://127.0.0.1:${port}`).replace(/\/$/, "");

const exactRoutes = new Map<string, ReadonlySet<string>>([
  ["/v1/health", new Set(["GET"])],
  ["/v1/health/config", new Set(["GET"])],
  ["/v1/health/ping", new Set(["GET"])],
  ["/v1/regions", new Set(["GET"])],
  ["/v1/matchmaking/join", new Set(["POST"])],
]);

function isAllowed(method: string, pathname: string): boolean {
  const exactMethods = exactRoutes.get(pathname);
  if (exactMethods?.has(method)) return true;
  if (method === "GET" && pathname.startsWith("/v1/matchmaking/status/")) return true;
  if (method === "DELETE" && pathname.startsWith("/v1/matchmaking/")) return true;
  return false;
}

function forwardedHeaders(request: Request): Headers {
  const headers = new Headers(request.headers);
  for (const name of [
    "host",
    "connection",
    "content-length",
    "transfer-encoding",
    "x-forwarded-for",
    "x-forwarded-host",
    "x-forwarded-port",
    "x-forwarded-proto",
    "x-real-ip",
    "x-rivet-token",
  ]) {
    headers.delete(name);
  }
  headers.set("x-colony-control-gateway", "rivet-actor");
  return headers;
}

function responseHeaders(source: Headers): Headers {
  const headers = new Headers(source);
  for (const name of ["connection", "content-length", "transfer-encoding"]) {
    headers.delete(name);
  }
  headers.set("cache-control", "no-store");
  headers.set("x-content-type-options", "nosniff");
  return headers;
}

export const controlApi = actor({
  options: {
    name: "Colony Public Control API",
    sleepTimeout: 60_000,
  },
  onRequest: async (_c, request): Promise<Response> => {
    const incomingUrl = new URL(request.url);
    const method = request.method.toUpperCase();
    if (!isAllowed(method, incomingUrl.pathname)) {
      return Response.json({ error: "not_found" }, { status: 404 });
    }

    const targetUrl = `${internalBaseUrl}${incomingUrl.pathname}${incomingUrl.search}`;
    const body = method === "GET" || method === "HEAD" ? undefined : await request.arrayBuffer();

    let upstream: Response;
    try {
      upstream = await fetch(targetUrl, {
        method,
        headers: forwardedHeaders(request),
        body,
        redirect: "manual",
        signal: AbortSignal.timeout(15_000),
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error("Public control gateway upstream failure", { method, path: incomingUrl.pathname, message });
      return Response.json({ error: "control_plane_unavailable" }, { status: 503 });
    }

    const payload = await upstream.arrayBuffer();
    return new Response(payload, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: responseHeaders(upstream.headers),
    });
  },
  actions: {
    metadata: () => ({
      service: "colony-dominion-public-control",
      buildId: process.env.SUPPORTED_BUILD_ID ?? "",
      protocolVersion: Number(process.env.PROTOCOL_VERSION ?? 0),
    }),
  },
});
