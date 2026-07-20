import { spawn, type ChildProcess } from "node:child_process";
import { createServer } from "node:net";
import { actor } from "rivetkit";

export type GameServerActorInput = {
  matchId: string;
  serverId: string;
  regionId: string;
  buildId: string;
  protocolVersion: number;
  expectedPlayers: number;
  maxPlayers: number;
  matchSeed: number;
  serverAuthToken: string;
};

type GameServerActorState = GameServerActorInput & {
  status: "starting" | "ready" | "failed" | "stopping";
  restartCount: number;
  startedAt: number;
  lastError: string;
};

type GameRuntime = {
  child: ChildProcess;
  gamePort: number;
  controlPort: number;
  ready: boolean;
  exited: boolean;
  exitCode: number | null;
  sockets: Set<WebSocket>;
  logs: string[];
};

const runtimes = new Map<string, GameRuntime>();
const MAX_LOG_LINES = 200;
const START_TIMEOUT_MS = 45_000;
const RESTART_LIMIT = 2;

function requireText(value: string, name: string): string {
  const cleaned = value.trim();
  if (!cleaned) throw new Error(`${name} is required`);
  return cleaned;
}

function requireInteger(value: number, name: string, minimum: number, maximum: number): number {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${name} must be an integer between ${minimum} and ${maximum}`);
  }
  return value;
}

async function reserveLoopbackPort(): Promise<number> {
  return await new Promise<number>((resolve, reject) => {
    const server = createServer();
    server.unref();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        server.close(() => reject(new Error("Could not reserve a loopback port")));
        return;
      }
      const port = address.port;
      server.close((error) => (error ? reject(error) : resolve(port)));
    });
  });
}

function appendLogs(runtime: GameRuntime, source: "stdout" | "stderr", chunk: Buffer): void {
  const lines = chunk.toString("utf8").split(/\r?\n/).filter(Boolean);
  for (const line of lines) runtime.logs.push(`[${source}] ${line.slice(0, 2_000)}`);
  if (runtime.logs.length > MAX_LOG_LINES) {
    runtime.logs.splice(0, runtime.logs.length - MAX_LOG_LINES);
  }
}

async function waitForGodotReady(runtime: GameRuntime): Promise<void> {
  const deadline = Date.now() + START_TIMEOUT_MS;
  const url = `http://127.0.0.1:${runtime.controlPort}/ready`;
  let lastError = "Godot readiness endpoint was not reachable";
  while (Date.now() < deadline) {
    if (runtime.exited) {
      throw new Error(`Godot exited before readiness (exit=${runtime.exitCode ?? "unknown"})`);
    }
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(1_500) });
      if (response.ok) {
        const body = (await response.json().catch(() => ({}))) as Record<string, unknown>;
        if (body.ready === true || body.ok === true) return;
        lastError = `Godot readiness response was not ready: ${JSON.stringify(body).slice(0, 500)}`;
      } else {
        lastError = `Godot readiness returned HTTP ${response.status}`;
      }
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`${lastError}; logs=${runtime.logs.slice(-20).join(" | ")}`);
}

async function startRuntime(actorId: string, state: GameServerActorState): Promise<GameRuntime> {
  const existing = runtimes.get(actorId);
  if (existing && !existing.exited) return existing;

  const gamePort = await reserveLoopbackPort();
  let controlPort = await reserveLoopbackPort();
  while (controlPort === gamePort) controlPort = await reserveLoopbackPort();

  const godotBinary = process.env.GODOT_BIN?.trim() || "/usr/local/bin/godot";
  const pckPath = process.env.GODOT_PCK_PATH?.trim() || "/app/game/colony-dominion-server.pck";
  const controlPortForParent = Number(process.env.RIVET_PORT ?? process.env.PORT ?? 3000);

  state.status = "starting";
  state.lastError = "";
  const child = spawn(
    godotBinary,
    ["--headless", "--main-pack", pckPath, "--server"],
    {
      cwd: "/app/game",
      env: {
        ...process.env,
        NETWORK_TRANSPORT: "websocket",
        MATCH_ID: state.matchId,
        SERVER_ID: state.serverId,
        REGION_ID: state.regionId,
        BUILD_ID: state.buildId,
        PROTOCOL_VERSION: String(state.protocolVersion),
        EXPECTED_PLAYERS: String(state.expectedPlayers),
        MAX_PLAYERS: String(state.maxPlayers),
        MATCH_SEED: String(state.matchSeed),
        GAME_SERVER_AUTH_TOKEN: state.serverAuthToken,
        CONTROL_BASE_URL: `http://127.0.0.1:${controlPortForParent}`,
        GAME_PORT: String(gamePort),
        CONTROL_PORT: String(controlPort),
        RANKED_MATCH: "1",
        HOME: "/tmp",
        XDG_DATA_HOME: "/tmp/.local/share",
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );

  const runtime: GameRuntime = {
    child,
    gamePort,
    controlPort,
    ready: false,
    exited: false,
    exitCode: null,
    sockets: new Set(),
    logs: [],
  };
  runtimes.set(actorId, runtime);
  child.stdout?.on("data", (chunk: Buffer) => appendLogs(runtime, "stdout", chunk));
  child.stderr?.on("data", (chunk: Buffer) => appendLogs(runtime, "stderr", chunk));
  child.once("exit", (code) => {
    runtime.exited = true;
    runtime.ready = false;
    runtime.exitCode = code;
    for (const socket of runtime.sockets) {
      try {
        socket.close(1011, "game_server_exited");
      } catch {
        // Connection may already be closed.
      }
    }
    runtime.sockets.clear();
  });

  try {
    await waitForGodotReady(runtime);
    runtime.ready = true;
    state.status = "ready";
    state.startedAt = Date.now();
    return runtime;
  } catch (error) {
    state.status = "failed";
    state.lastError = error instanceof Error ? error.message : String(error);
    await stopRuntime(actorId);
    throw error;
  }
}

async function stopRuntime(actorId: string): Promise<void> {
  const runtime = runtimes.get(actorId);
  if (!runtime) return;
  runtimes.delete(actorId);
  for (const socket of runtime.sockets) {
    try {
      socket.close(1001, "actor_stopping");
    } catch {
      // Connection may already be closed.
    }
  }
  runtime.sockets.clear();
  if (runtime.exited) return;

  await new Promise<void>((resolve) => {
    const timeout = setTimeout(() => {
      if (!runtime.exited) runtime.child.kill("SIGKILL");
      resolve();
    }, 5_000);
    timeout.unref();
    runtime.child.once("exit", () => {
      clearTimeout(timeout);
      resolve();
    });
    runtime.child.kill("SIGTERM");
  });
}

async function openGodotSocket(runtime: GameRuntime): Promise<WebSocket> {
  const socket = new WebSocket(`ws://127.0.0.1:${runtime.gamePort}`);
  socket.binaryType = "arraybuffer";
  await new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => {
      socket.close();
      reject(new Error("Timed out connecting to local Godot WebSocket server"));
    }, 5_000);
    timeout.unref();
    socket.addEventListener("open", () => {
      clearTimeout(timeout);
      resolve();
    }, { once: true });
    socket.addEventListener("error", () => {
      clearTimeout(timeout);
      reject(new Error("Could not connect to local Godot WebSocket server"));
    }, { once: true });
  });
  return socket;
}

async function normalizeSocketPayload(value: unknown): Promise<string | ArrayBuffer> {
  if (typeof value === "string") return value;
  if (value instanceof ArrayBuffer) return value;
  if (ArrayBuffer.isView(value)) {
    return value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength) as ArrayBuffer;
  }
  if (value instanceof Blob) return await value.arrayBuffer();
  throw new Error("Unsupported WebSocket payload type");
}

function bridgeSockets(context: { waitUntil: (promise: Promise<unknown>) => void }, downstream: WebSocket, upstream: WebSocket, runtime: GameRuntime): void {
  downstream.binaryType = "arraybuffer";
  runtime.sockets.add(downstream);

  downstream.addEventListener("message", (event) => {
    const task = normalizeSocketPayload(event.data).then((payload) => {
      if (upstream.readyState === WebSocket.OPEN) upstream.send(payload);
    });
    context.waitUntil(task);
  });
  upstream.addEventListener("message", (event) => {
    const task = normalizeSocketPayload(event.data).then((payload) => {
      if (downstream.readyState === WebSocket.OPEN) downstream.send(payload);
    });
    context.waitUntil(task);
  });

  const closeBoth = (code: number, reason: string): void => {
    runtime.sockets.delete(downstream);
    try {
      if (downstream.readyState === WebSocket.OPEN) downstream.close(code, reason);
    } catch {
      // Ignore close races.
    }
    try {
      if (upstream.readyState === WebSocket.OPEN) upstream.close(code, reason);
    } catch {
      // Ignore close races.
    }
  };
  downstream.addEventListener("close", () => closeBoth(1000, "client_closed"), { once: true });
  upstream.addEventListener("close", () => closeBoth(1011, "game_server_closed"), { once: true });
  downstream.addEventListener("error", () => closeBoth(1011, "client_socket_error"), { once: true });
  upstream.addEventListener("error", () => closeBoth(1011, "game_server_socket_error"), { once: true });
}

export const gameServer = actor({
  createState: (_c, input: GameServerActorInput): GameServerActorState => ({
    matchId: requireText(input.matchId, "matchId"),
    serverId: requireText(input.serverId, "serverId"),
    regionId: requireText(input.regionId, "regionId"),
    buildId: requireText(input.buildId, "buildId"),
    protocolVersion: requireInteger(input.protocolVersion, "protocolVersion", 1, 65_535),
    expectedPlayers: requireInteger(input.expectedPlayers, "expectedPlayers", 1, 10),
    maxPlayers: requireInteger(input.maxPlayers, "maxPlayers", input.expectedPlayers, 10),
    matchSeed: requireInteger(input.matchSeed, "matchSeed", 1, 2_147_483_647),
    serverAuthToken: requireText(input.serverAuthToken, "serverAuthToken"),
    status: "starting",
    restartCount: 0,
    startedAt: 0,
    lastError: "",
  }),
  options: {
    sleepTimeout: 4 * 60 * 60 * 1_000,
    sleepGracePeriod: 30_000,
    actionTimeout: 60_000,
    canHibernateWebSocket: false,
  },
  onWake: async (c) => {
    await startRuntime(c.actorId, c.state);
  },
  run: async (c) => {
    while (!c.aborted) {
      await new Promise((resolve) => setTimeout(resolve, 1_000));
      const runtime = runtimes.get(c.actorId);
      if (runtime && !runtime.exited) continue;
      if (c.state.status === "stopping") return;
      if (c.state.restartCount >= RESTART_LIMIT) {
        c.state.status = "failed";
        c.state.lastError = runtime?.logs.slice(-20).join(" | ") || "Godot process restart limit reached";
        c.destroy();
        return;
      }
      c.state.restartCount += 1;
      await startRuntime(c.actorId, c.state);
    }
  },
  onSleep: async (c) => {
    c.state.status = "stopping";
    await stopRuntime(c.actorId);
  },
  onDestroy: async (c) => {
    c.state.status = "stopping";
    await stopRuntime(c.actorId);
  },
  onRequest: async (c, request) => {
    const path = new URL(request.url).pathname;
    if (request.method === "GET" && (path === "/ready" || path.endsWith("/ready"))) {
      const runtime = runtimes.get(c.actorId);
      const ready = Boolean(runtime?.ready && !runtime.exited && c.state.status === "ready");
      return Response.json({
        ok: ready,
        ready,
        status: c.state.status,
        match_id: c.state.matchId,
        server_id: c.state.serverId,
        restart_count: c.state.restartCount,
      }, { status: ready ? 200 : 503 });
    }
    return Response.json({ error: "not_found" }, { status: 404 });
  },
  onWebSocket: async (c, websocket) => {
    const runtime = await startRuntime(c.actorId, c.state);
    if (!runtime.ready || runtime.exited) throw new Error("Godot game server is not ready");
    const upstream = await openGodotSocket(runtime);
    bridgeSockets(c, websocket, upstream, runtime);
  },
  actions: {
    getStatus: (c) => {
      const runtime = runtimes.get(c.actorId);
      return {
        status: c.state.status,
        matchId: c.state.matchId,
        serverId: c.state.serverId,
        regionId: c.state.regionId,
        ready: Boolean(runtime?.ready && !runtime.exited),
        restartCount: c.state.restartCount,
        startedAt: c.state.startedAt,
        lastError: c.state.lastError,
      };
    },
    shutdown: (c, _reason: string = "match_complete") => {
      c.state.status = "stopping";
      c.destroy();
      return { ok: true };
    },
  },
});
