import { createHash, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { mkdir, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import { createServer, request as nodeRequest } from "node:http";
import { join, resolve } from "node:path";

const MANAGED_LABEL = "io.colony.managed";
const ALLOCATION_LABEL = "io.colony.allocation_key";
const MAX_EXPIRES_LABEL = "io.colony.max_expires_at";
const SERVER_ID_LABEL = "io.colony.server_id";
const MATCH_ID_LABEL = "io.colony.match_id";
const GAME_PRIVATE_PORT = "7000/udp";
const CONTROL_PRIVATE_PORT = "7001/tcp";
const MAX_BODY_BYTES = 64 * 1024;

function required(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function positiveInt(name, fallback, min = 1, max = Number.MAX_SAFE_INTEGER) {
  const raw = process.env[name]?.trim();
  const value = raw ? Number(raw) : fallback;
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new Error(`${name} must be an integer between ${min} and ${max}`);
  }
  return value;
}

const config = Object.freeze({
  port: positiveInt("PORT", 8080, 1, 65535),
  sharedToken: required("ALLOCATOR_SHARED_TOKEN"),
  publicGameHost: required("PUBLIC_GAME_HOST"),
  controlBaseUrl: required("CONTROL_BASE_URL").replace(/\/$/, ""),
  gameServerImage: required("GAME_SERVER_IMAGE"),
  dockerSocket: process.env.DOCKER_SOCKET?.trim() || "/var/run/docker.sock",
  dockerApiVersion: process.env.DOCKER_API_VERSION?.trim() || "v1.41",
  dockerNetwork: process.env.GAME_SERVER_DOCKER_NETWORK?.trim() || "colony-staging",
  dataDir: resolve(process.env.ALLOCATOR_DATA_DIR?.trim() || "/data/allocations"),
  gamePortMin: positiveInt("GAME_PORT_MIN", 20000, 1024, 65535),
  gamePortMax: positiveInt("GAME_PORT_MAX", 20015, 1024, 65535),
  controlPortMin: positiveInt("CONTROL_PORT_MIN", 21000, 1024, 65535),
  controlPortMax: positiveInt("CONTROL_PORT_MAX", 21015, 1024, 65535),
  maxConcurrentServers: positiveInt("MAX_CONCURRENT_SERVERS", 4, 1, 64),
  serverCpuMillicores: positiveInt("GAME_SERVER_CPU_MILLICORES", 500, 100, 8000),
  serverMemoryMb: positiveInt("GAME_SERVER_MEMORY_MB", 512, 128, 32768),
  assignmentTtlMs: positiveInt("ASSIGNMENT_TTL_SECONDS", 120, 30, 900) * 1000,
  serverMaxLifetimeMs: positiveInt("SERVER_MAX_LIFETIME_SECONDS", 14400, 300, 86400) * 1000,
  readinessTimeoutMs: positiveInt("SERVER_READY_TIMEOUT_SECONDS", 45, 5, 180) * 1000,
  supportedBuildId: process.env.SUPPORTED_BUILD_ID?.trim() || "",
  protocolVersion: positiveInt("PROTOCOL_VERSION", 3, 1, 65535),
  maxPlayers: positiveInt("MAX_PLAYERS", 6, 1, 32),
});

if (config.gamePortMax < config.gamePortMin) throw new Error("GAME_PORT_MAX must be >= GAME_PORT_MIN");
if (config.controlPortMax < config.controlPortMin) throw new Error("CONTROL_PORT_MAX must be >= CONTROL_PORT_MIN");

const allocationLocks = new Map();
let globalMutation = Promise.resolve();

function sha256(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function secureTokenEqual(left, right) {
  const leftHash = createHash("sha256").update(left, "utf8").digest();
  const rightHash = createHash("sha256").update(right, "utf8").digest();
  return timingSafeEqual(leftHash, rightHash);
}

function bearerToken(request) {
  const value = request.headers.authorization || "";
  return value.startsWith("Bearer ") ? value.slice("Bearer ".length) : "";
}

function randomToken() {
  return randomBytes(32).toString("base64url");
}

function isObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nonEmptyString(value, name, maxLength = 256) {
  if (typeof value !== "string" || value.trim().length === 0 || value.length > maxLength) {
    throw new HttpError(400, `${name} must be a non-empty string up to ${maxLength} characters`);
  }
  return value.trim();
}

function positiveInteger(value, name, max = Number.MAX_SAFE_INTEGER) {
  if (!Number.isInteger(value) || value <= 0 || value > max) {
    throw new HttpError(400, `${name} must be a positive integer`);
  }
  return value;
}

function validateAllocationRequest(value) {
  if (!isObject(value)) throw new HttpError(400, "Request body must be a JSON object");
  const regionId = nonEmptyString(value.region_id, "region_id", 32);
  const providerRegion = typeof value.provider_region === "string" ? value.provider_region.trim() : "";
  const buildId = nonEmptyString(value.build_id, "build_id", 96);
  const protocolVersion = positiveInteger(value.protocol_version, "protocol_version", 65535);
  if (!Array.isArray(value.players) || value.players.length === 0 || value.players.length > config.maxPlayers) {
    throw new HttpError(400, `players must contain between 1 and ${config.maxPlayers} entries`);
  }
  const players = value.players.map((player, index) => {
    if (!isObject(player)) throw new HttpError(400, `players[${index}] must be an object`);
    return {
      playerId: nonEmptyString(player.player_id, `players[${index}].player_id`, 64),
      queueTicketId: nonEmptyString(player.queue_ticket_id, `players[${index}].queue_ticket_id`, 256),
    };
  });
  const queueIds = new Set(players.map((player) => player.queueTicketId));
  if (queueIds.size !== players.length) throw new HttpError(400, "queue_ticket_id values must be unique");
  const requestedAllocationKey = typeof value.allocation_key === "string" ? value.allocation_key.trim() : "";
  if (requestedAllocationKey && !/^[0-9a-f]{64}$/i.test(requestedAllocationKey)) {
    throw new HttpError(400, "allocation_key must be a SHA-256 hex string");
  }
  const derivedAllocationKey = sha256(JSON.stringify({
    regionId,
    buildId,
    protocolVersion,
    queueTicketIds: [...queueIds].sort(),
  }));
  if (requestedAllocationKey && requestedAllocationKey.toLowerCase() !== derivedAllocationKey) {
    throw new HttpError(409, "allocation_key does not match the allocation payload");
  }
  if (config.supportedBuildId && buildId !== config.supportedBuildId) {
    throw new HttpError(409, "unsupported_build_id");
  }
  if (protocolVersion !== config.protocolVersion) {
    throw new HttpError(409, "protocol_version_mismatch");
  }
  return {
    regionId,
    providerRegion,
    buildId,
    protocolVersion,
    players,
    allocationKey: derivedAllocationKey,
  };
}

class HttpError extends Error {
  constructor(status, message, detail = undefined) {
    super(message);
    this.status = status;
    this.detail = detail;
  }
}

class DockerError extends Error {
  constructor(status, method, path, body) {
    super(`Docker API ${method} ${path} failed with HTTP ${status}`);
    this.status = status;
    this.body = body;
  }
}

function dockerRequest(method, path, body = undefined, accepted = [200, 201, 204]) {
  const payload = body === undefined ? undefined : Buffer.from(JSON.stringify(body));
  const apiPath = path === "/_ping" ? path : `/${config.dockerApiVersion}${path}`;
  return new Promise((resolvePromise, rejectPromise) => {
    const request = nodeRequest({
      socketPath: config.dockerSocket,
      path: apiPath,
      method,
      headers: payload ? {
        "content-type": "application/json",
        "content-length": String(payload.length),
      } : undefined,
    }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
      response.on("end", () => {
        const raw = Buffer.concat(chunks).toString("utf8");
        const status = response.statusCode || 0;
        if (!accepted.includes(status)) {
          rejectPromise(new DockerError(status, method, path, raw.slice(0, 2000)));
          return;
        }
        if (!raw) {
          resolvePromise(undefined);
          return;
        }
        try {
          resolvePromise(JSON.parse(raw));
        } catch {
          resolvePromise(raw);
        }
      });
    });
    request.on("error", rejectPromise);
    if (payload) request.write(payload);
    request.end();
  });
}

async function dockerPing() {
  const response = await dockerRequest("GET", "/_ping", undefined, [200]);
  if (String(response).trim() !== "OK") throw new Error("Docker daemon ping did not return OK");
}

async function inspectImage() {
  await dockerRequest("GET", `/images/${encodeURIComponent(config.gameServerImage)}/json`, undefined, [200]);
}

async function listManagedContainers(all = true) {
  const filters = encodeURIComponent(JSON.stringify({ label: [`${MANAGED_LABEL}=true`] }));
  const result = await dockerRequest("GET", `/containers/json?all=${all ? "1" : "0"}&filters=${filters}`, undefined, [200]);
  return Array.isArray(result) ? result : [];
}

async function inspectContainer(containerId) {
  const result = await dockerRequest("GET", `/containers/${encodeURIComponent(containerId)}/json`, undefined, [200]);
  return isObject(result) ? result : {};
}

async function removeContainer(containerId) {
  try {
    await dockerRequest("DELETE", `/containers/${encodeURIComponent(containerId)}?force=true&v=true`, undefined, [204, 404]);
  } catch (error) {
    if (!(error instanceof DockerError && error.status === 404)) throw error;
  }
}

function statePath(allocationKey) {
  return join(config.dataDir, `${allocationKey}.json`);
}

async function readAllocationState(allocationKey) {
  try {
    const parsed = JSON.parse(await readFile(statePath(allocationKey), "utf8"));
    return isObject(parsed) ? parsed : null;
  } catch (error) {
    if (error && typeof error === "object" && error.code === "ENOENT") return null;
    throw error;
  }
}

async function writeAllocationState(allocationKey, state) {
  await mkdir(config.dataDir, { recursive: true, mode: 0o700 });
  const path = statePath(allocationKey);
  const temporary = `${path}.${process.pid}.${randomUUID()}.tmp`;
  await writeFile(temporary, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
  await rename(temporary, path);
}

async function deleteAllocationState(allocationKey) {
  await rm(statePath(allocationKey), { force: true });
}

async function withGlobalMutation(callback) {
  const previous = globalMutation;
  let release;
  globalMutation = new Promise((resolvePromise) => { release = resolvePromise; });
  await previous.catch(() => undefined);
  try {
    return await callback();
  } finally {
    release();
  }
}

async function withAllocationLock(allocationKey, callback) {
  const previous = allocationLocks.get(allocationKey) || Promise.resolve();
  const run = previous.catch(() => undefined).then(callback);
  allocationLocks.set(allocationKey, run);
  try {
    return await run;
  } finally {
    if (allocationLocks.get(allocationKey) === run) allocationLocks.delete(allocationKey);
  }
}

function portIsUsed(containers, port, type) {
  return containers.some((container) => Array.isArray(container.Ports) && container.Ports.some((binding) =>
    binding && binding.PublicPort === port && binding.Type === type
  ));
}

function firstFreePort(containers, min, max, type) {
  for (let port = min; port <= max; port += 1) {
    if (!portIsUsed(containers, port, type)) return port;
  }
  return 0;
}

async function waitForReady(controlPort, containerId) {
  const deadline = Date.now() + config.readinessTimeoutMs;
  const url = `http://127.0.0.1:${controlPort}/ready`;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(1500) });
      if (response.ok) return;
    } catch {
    }
    const inspect = await inspectContainer(containerId).catch(() => ({}));
    const state = isObject(inspect.State) ? inspect.State : {};
    if (state.Running === false) {
      throw new Error(`Game-server container exited before readiness (exit=${state.ExitCode ?? "unknown"})`);
    }
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 500));
  }
  throw new Error(`Game-server readiness timed out after ${config.readinessTimeoutMs}ms`);
}

async function reuseExistingState(state) {
  const containerId = typeof state.container_id === "string" ? state.container_id : "";
  const maxExpiresAt = Number(state.max_expires_at || 0);
  if (!containerId || maxExpiresAt <= Date.now() || !isObject(state.response)) return null;
  try {
    const inspect = await inspectContainer(containerId);
    const containerState = isObject(inspect.State) ? inspect.State : {};
    return containerState.Running === true ? state.response : null;
  } catch (error) {
    if (error instanceof DockerError && error.status === 404) return null;
    throw error;
  }
}

async function cleanupExpiredAllocations() {
  await mkdir(config.dataDir, { recursive: true, mode: 0o700 });
  const now = Date.now();
  const files = (await readdir(config.dataDir)).filter((name) => /^[0-9a-f]{64}\.json$/i.test(name));
  const liveContainerIds = new Set();
  for (const file of files) {
    const allocationKey = file.slice(0, -5);
    const state = await readAllocationState(allocationKey).catch(() => null);
    if (!state) {
      await deleteAllocationState(allocationKey);
      continue;
    }
    const containerId = typeof state.container_id === "string" ? state.container_id : "";
    const maxExpiresAt = Number(state.max_expires_at || 0);
    if (containerId && maxExpiresAt > now) {
      liveContainerIds.add(containerId);
      continue;
    }
    if (containerId) await removeContainer(containerId).catch((error) => console.error("cleanup remove failed", error));
    await deleteAllocationState(allocationKey);
  }

  const containers = await listManagedContainers(true);
  for (const container of containers) {
    const id = typeof container.Id === "string" ? container.Id : "";
    if (!id || liveContainerIds.has(id)) continue;
    const labels = isObject(container.Labels) ? container.Labels : {};
    const maxExpiresAt = Number(labels[MAX_EXPIRES_LABEL] || 0);
    const createdSeconds = Number(container.Created || 0);
    const orphanExpired = maxExpiresAt > 0 ? maxExpiresAt <= now : createdSeconds * 1000 + 10 * 60 * 1000 <= now;
    if (orphanExpired) await removeContainer(id).catch((error) => console.error("orphan remove failed", error));
  }
}

async function createAllocation(request) {
  return await withGlobalMutation(async () => {
    await cleanupExpiredAllocations();
    const existingState = await readAllocationState(request.allocationKey);
    if (existingState) {
      const reused = await reuseExistingState(existingState);
      if (reused) return reused;
      const staleContainerId = typeof existingState.container_id === "string" ? existingState.container_id : "";
      if (staleContainerId) await removeContainer(staleContainerId).catch(() => undefined);
      await deleteAllocationState(request.allocationKey);
    }

    await inspectImage();
    const running = await listManagedContainers(false);
    if (running.length >= config.maxConcurrentServers) {
      throw new HttpError(503, "allocator_capacity_exhausted", {
        active: running.length,
        limit: config.maxConcurrentServers,
      });
    }
    const allContainers = await listManagedContainers(true);
    const gamePort = firstFreePort(allContainers, config.gamePortMin, config.gamePortMax, "udp");
    const controlPort = firstFreePort(allContainers, config.controlPortMin, config.controlPortMax, "tcp");
    if (!gamePort || !controlPort) throw new HttpError(503, "allocator_port_range_exhausted");

    const now = Date.now();
    const matchId = randomUUID();
    const serverId = randomUUID();
    const serverAuthToken = randomToken();
    const joinTickets = Object.fromEntries(request.players.map((player) => [player.queueTicketId, randomToken()]));
    const assignmentExpiresAt = now + config.assignmentTtlMs;
    const maxExpiresAt = now + config.serverMaxLifetimeMs;
    const containerName = `colony-match-${serverId.slice(0, 12)}`;
    const labels = {
      [MANAGED_LABEL]: "true",
      [ALLOCATION_LABEL]: request.allocationKey,
      [MAX_EXPIRES_LABEL]: String(maxExpiresAt),
      [SERVER_ID_LABEL]: serverId,
      [MATCH_ID_LABEL]: matchId,
    };
    const env = [
      `MATCH_ID=${matchId}`,
      `SERVER_ID=${serverId}`,
      `REGION_ID=${request.regionId}`,
      `BUILD_ID=${request.buildId}`,
      `PROTOCOL_VERSION=${request.protocolVersion}`,
      `CONTROL_BASE_URL=${config.controlBaseUrl}`,
      `GAME_SERVER_AUTH_TOKEN=${serverAuthToken}`,
      `MAX_PLAYERS=${config.maxPlayers}`,
      `EXPECTED_PLAYERS=${request.players.length}`,
      "GAME_PORT=7000",
      "CONTROL_PORT=7001",
      "RANKED_MATCH=1",
      "HOME=/tmp",
      "XDG_DATA_HOME=/tmp/.local/share",
    ];
    let containerId = "";
    try {
      const created = await dockerRequest("POST", `/containers/create?name=${encodeURIComponent(containerName)}`, {
        Image: config.gameServerImage,
        Env: env,
        Labels: labels,
        ExposedPorts: {
          [GAME_PRIVATE_PORT]: {},
          [CONTROL_PRIVATE_PORT]: {},
        },
        HostConfig: {
          NetworkMode: config.dockerNetwork,
          PortBindings: {
            [GAME_PRIVATE_PORT]: [{ HostIp: "0.0.0.0", HostPort: String(gamePort) }],
            [CONTROL_PRIVATE_PORT]: [{ HostIp: "127.0.0.1", HostPort: String(controlPort) }],
          },
          RestartPolicy: { Name: "no" },
          AutoRemove: false,
          Memory: config.serverMemoryMb * 1024 * 1024,
          NanoCpus: config.serverCpuMillicores * 1_000_000,
          PidsLimit: 256,
          ReadonlyRootfs: true,
          Tmpfs: { "/tmp": "rw,noexec,nosuid,size=128m,mode=1777" },
          SecurityOpt: ["no-new-privileges:true"],
          CapDrop: ["ALL"],
          LogConfig: { Type: "json-file", Config: { "max-size": "10m", "max-file": "3" } },
        },
        StopTimeout: 10,
      });
      containerId = isObject(created) && typeof created.Id === "string" ? created.Id : "";
      if (!containerId) throw new Error("Docker create response did not include a container id");
      await dockerRequest("POST", `/containers/${encodeURIComponent(containerId)}/start`, undefined, [204]);
      await waitForReady(controlPort, containerId);

      const response = {
        assignment: {
          match_id: matchId,
          server_id: serverId,
          host: config.publicGameHost,
          port: gamePort,
          region_id: request.regionId,
          expires_at: assignmentExpiresAt,
          protocol_version: request.protocolVersion,
        },
        join_tickets: joinTickets,
        server_auth_token: serverAuthToken,
      };
      await writeAllocationState(request.allocationKey, {
        allocation_key: request.allocationKey,
        container_id: containerId,
        created_at: now,
        max_expires_at: maxExpiresAt,
        response,
      });
      return response;
    } catch (error) {
      if (containerId) await removeContainer(containerId).catch(() => undefined);
      throw error;
    }
  });
}

async function allocate(request) {
  return await withAllocationLock(request.allocationKey, () => createAllocation(request));
}

async function parseJsonBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new HttpError(413, "request_body_too_large");
    chunks.push(Buffer.from(chunk));
  }
  if (chunks.length === 0) throw new HttpError(400, "request_body_required");
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new HttpError(400, "invalid_json");
  }
}

function sendJson(response, status, body) {
  const payload = Buffer.from(JSON.stringify(body));
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": String(payload.length),
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
  });
  response.end(payload);
}

async function handle(request, response) {
  const url = new URL(request.url || "/", "http://allocator.local");
  if (request.method === "GET" && url.pathname === "/health") {
    try {
      await dockerPing();
      await inspectImage();
      const running = await listManagedContainers(false);
      sendJson(response, 200, {
        ok: true,
        service: "colony-external-allocator",
        docker: true,
        image: config.gameServerImage,
        active_servers: running.length,
        capacity: config.maxConcurrentServers,
        game_port_range: [config.gamePortMin, config.gamePortMax],
      });
    } catch (error) {
      sendJson(response, 503, { ok: false, error: error instanceof Error ? error.message : String(error) });
    }
    return;
  }
  if (request.method === "POST" && url.pathname === "/allocate") {
    const token = bearerToken(request);
    if (!token || !secureTokenEqual(token, config.sharedToken)) {
      sendJson(response, 401, { error: "unauthorized" });
      return;
    }
    try {
      const parsed = validateAllocationRequest(await parseJsonBody(request));
      const result = await allocate(parsed);
      sendJson(response, 200, result);
    } catch (error) {
      if (error instanceof HttpError) {
        sendJson(response, error.status, { error: error.message, detail: error.detail });
        return;
      }
      if (error instanceof DockerError) {
        console.error("Docker allocation error", error.status, error.body);
        sendJson(response, 502, { error: "docker_allocation_failed", status: error.status });
        return;
      }
      console.error("Allocator error", error);
      sendJson(response, 500, { error: "allocator_internal_error" });
    }
    return;
  }
  sendJson(response, 404, { error: "not_found" });
}

await mkdir(config.dataDir, { recursive: true, mode: 0o700 });
await dockerPing();
setInterval(() => cleanupExpiredAllocations().catch((error) => console.error("scheduled cleanup failed", error)), 60_000).unref();

const server = createServer((request, response) => {
  handle(request, response).catch((error) => {
    console.error("Unhandled request error", error);
    if (!response.headersSent) sendJson(response, 500, { error: "allocator_internal_error" });
    else response.destroy();
  });
});
server.requestTimeout = 70_000;
server.headersTimeout = 10_000;
server.keepAliveTimeout = 5_000;
server.listen(config.port, "0.0.0.0", () => {
  console.log(JSON.stringify({
    ok: true,
    service: "colony-external-allocator",
    port: config.port,
    image: config.gameServerImage,
    public_game_host: config.publicGameHost,
    max_concurrent_servers: config.maxConcurrentServers,
  }));
});
