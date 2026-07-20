import { mkdir, open, stat, writeFile } from "node:fs/promises";
import { basename, dirname, resolve } from "node:path";
import { RivetClient } from "@rivet-gg/api";

type JsonRecord = Record<string, unknown>;

type RivetContext = {
  project: string;
  environment: string;
  projectId: string;
  environmentId: string;
};

function requireEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function asRecord(value: unknown): JsonRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return {};
  return value as JsonRecord;
}

function readString(record: JsonRecord, ...keys: string[]): string {
  for (const key of keys) {
    const value = record[key];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
}

function readRecord(record: JsonRecord, ...keys: string[]): JsonRecord {
  for (const key of keys) {
    const value = asRecord(record[key]);
    if (Object.keys(value).length > 0) return value;
  }
  return {};
}

function readRecords(record: JsonRecord, ...keys: string[]): JsonRecord[] {
  for (const key of keys) {
    const value = record[key];
    if (Array.isArray(value)) return value.map(asRecord).filter((entry) => Object.keys(entry).length > 0);
  }
  return [];
}

function normalizeIdentifier(value: string): string {
  return value.toLocaleLowerCase("en-US").replace(/[^a-z0-9]+/g, "");
}

function resourceIdentifiers(record: JsonRecord, kind: "project" | "environment"): string[] {
  const idKeys = kind === "project"
    ? ["game_id", "gameId", "project_id", "projectId", "name_id", "nameId", "display_name", "displayName"]
    : ["namespace_id", "namespaceId", "environment_id", "environmentId", "name_id", "nameId", "display_name", "displayName"];
  return idKeys.map((key) => readString(record, key)).filter(Boolean);
}

function selectResource(
  records: JsonRecord[],
  requested: string,
  kind: "project" | "environment",
): JsonRecord {
  const requestedLower = requested.toLocaleLowerCase("en-US");
  const direct = records.filter((record) =>
    resourceIdentifiers(record, kind).some(
      (identifier) => identifier.toLocaleLowerCase("en-US") === requestedLower,
    ),
  );
  if (direct.length === 1) return direct[0]!;

  const normalized = normalizeIdentifier(requested);
  const normalizedMatches = records.filter((record) =>
    resourceIdentifiers(record, kind).some(
      (identifier) => normalizeIdentifier(identifier) === normalized,
    ),
  );
  if (normalizedMatches.length === 1) return normalizedMatches[0]!;

  const visible = records
    .map((record) => {
      const values = resourceIdentifiers(record, kind);
      return values.length > 0 ? values.join(" / ") : "unnamed";
    })
    .join(", ");
  if (direct.length + normalizedMatches.length === 0) {
    throw new Error(
      `RIVET_${kind.toUpperCase()}_NOT_FOUND: requested ${JSON.stringify(requested)}; accessible: ${visible || "none"}`,
    );
  }
  throw new Error(
    `RIVET_${kind.toUpperCase()}_AMBIGUOUS: requested ${JSON.stringify(requested)}; matches: ${visible}`,
  );
}

async function cloudGet(path: string, token: string): Promise<JsonRecord> {
  const response = await fetch(`https://api.rivet.gg${path}`, {
    method: "GET",
    headers: {
      accept: "application/json",
      authorization: `Bearer ${token}`,
      "x-api-version": "25.5.3",
      "user-agent": "colony-dominion-deployer/05.3.1",
    },
  });
  const bodyText = await response.text();
  let body: unknown = {};
  try {
    body = bodyText ? JSON.parse(bodyText) : {};
  } catch {
    body = {};
  }
  if (!response.ok) {
    const detail = bodyText.slice(0, 800).replace(/\s+/g, " ");
    throw new Error(`RIVET_CONTEXT_HTTP_${response.status}: ${path}: ${detail}`);
  }
  return asRecord(body);
}

async function resolveRivetContext(
  token: string,
  requestedProject: string,
  requestedEnvironment: string,
): Promise<RivetContext> {
  const inspect = await cloudGet("/cloud/auth/inspect", token);
  const agent = readRecord(inspect, "agent");
  const gameCloud = readRecord(agent, "game_cloud", "gameCloud");
  let projectId = readString(gameCloud, "game_id", "gameId", "project_id", "projectId");
  let project: JsonRecord = {};

  if (projectId) {
    const projectResponse = await cloudGet(`/cloud/games/${encodeURIComponent(projectId)}`, token);
    project = readRecord(projectResponse, "game", "project");
  } else {
    const projectsResponse = await cloudGet("/cloud/games", token);
    const accessibleProjects = readRecords(projectsResponse, "games", "projects");
    if (!requestedProject) {
      if (accessibleProjects.length !== 1) {
        throw new Error(
          `RIVET_PROJECT_REQUIRED: token can access ${accessibleProjects.length} projects; set RIVET_PROJECT to an exact name`,
        );
      }
      project = accessibleProjects[0]!;
    } else {
      project = selectResource(accessibleProjects, requestedProject, "project");
    }
    projectId = readString(project, "game_id", "gameId", "project_id", "projectId");
    if (!projectId) throw new Error("RIVET_PROJECT_ID_MISSING: selected project has no id");
    const projectResponse = await cloudGet(`/cloud/games/${encodeURIComponent(projectId)}`, token);
    project = readRecord(projectResponse, "game", "project");
  }

  const projectNameId = readString(project, "name_id", "nameId");
  const projectDisplayName = readString(project, "display_name", "displayName");
  if (!projectNameId) throw new Error("RIVET_PROJECT_NAME_ID_MISSING: token project has no name_id");

  if (
    requestedProject &&
    ![projectId, projectNameId, projectDisplayName]
      .filter(Boolean)
      .some((value) => normalizeIdentifier(value) === normalizeIdentifier(requestedProject))
  ) {
    console.warn(
      `[Rivet] Configured project ${JSON.stringify(requestedProject)} does not match the token-scoped project; using ${JSON.stringify(projectNameId)}.`,
    );
  }

  const environments = readRecords(project, "namespaces", "environments");
  const selectedEnvironment = selectResource(
    environments,
    requestedEnvironment,
    "environment",
  );
  const environmentNameId = readString(selectedEnvironment, "name_id", "nameId");
  const environmentId = readString(
    selectedEnvironment,
    "namespace_id",
    "namespaceId",
    "environment_id",
    "environmentId",
  );
  if (!environmentNameId || !environmentId) {
    throw new Error("RIVET_ENVIRONMENT_METADATA_MISSING: selected environment has no name_id or id");
  }

  return {
    project: projectNameId,
    environment: environmentNameId,
    projectId,
    environmentId,
  };
}

async function writeResolvedContext(context: RivetContext): Promise<void> {
  const output = process.env.RIVET_CONTEXT_OUTPUT?.trim();
  if (!output) return;
  for (const value of Object.values(context)) {
    if (/[\r\n]/.test(value)) throw new Error("Resolved Rivet context contains an invalid newline");
  }
  const outputPath = resolve(output);
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(
    outputPath,
    [
      `RIVET_PROJECT=${context.project}`,
      `RIVET_ENVIRONMENT=${context.environment}`,
      `RIVET_PROJECT_ID=${context.projectId}`,
      `RIVET_ENVIRONMENT_ID=${context.environmentId}`,
      "",
    ].join("\n"),
    "utf8",
  );
}

async function uploadChunk(
  archivePath: string,
  url: string,
  byteOffset: number,
  contentLength: number,
): Promise<void> {
  if (!Number.isSafeInteger(byteOffset) || byteOffset < 0) {
    throw new Error(`Invalid upload byte offset: ${byteOffset}`);
  }
  if (!Number.isSafeInteger(contentLength) || contentLength <= 0) {
    throw new Error(`Invalid upload content length: ${contentLength}`);
  }
  const file = await open(archivePath, "r");
  try {
    const buffer = Buffer.allocUnsafe(contentLength);
    const { bytesRead } = await file.read(buffer, 0, contentLength, byteOffset);
    if (bytesRead !== contentLength) {
      throw new Error(`Read ${bytesRead} bytes, expected ${contentLength}`);
    }
    const response = await fetch(url, {
      method: "PUT",
      headers: {
        "content-type": "application/octet-stream",
        "content-length": String(contentLength),
      },
      body: buffer,
    });
    if (!response.ok) {
      throw new Error(`Presigned upload failed with HTTP ${response.status}`);
    }
  } finally {
    await file.close();
  }
}

async function main(): Promise<void> {
  const token = requireEnv("RIVET_CLOUD_TOKEN");
  const requestedProject = process.env.RIVET_PROJECT?.trim() ?? "";
  const requestedEnvironment = process.env.RIVET_ENVIRONMENT?.trim() || "staging";
  const context = await resolveRivetContext(token, requestedProject, requestedEnvironment);
  await writeResolvedContext(context);
  console.log(
    `[Rivet] Resolved project=${context.project} (${context.projectId}) environment=${context.environment} (${context.environmentId})`,
  );

  const imageTag = requireEnv("RIVET_GAME_SERVER_BUILD_TAG");
  const archivePath = resolve(requireEnv("RIVET_BUILD_ARCHIVE"));
  const archiveStat = await stat(archivePath);
  if (!archiveStat.isFile() || archiveStat.size <= 0) {
    throw new Error("RIVET_BUILD_ARCHIVE must point to a non-empty docker-save tar archive");
  }

  const client = new RivetClient({ token });
  const prepared = await client.builds.prepare(
    {
      project: context.project,
      environment: context.environment,
      body: {
        imageTag,
        imageFile: {
          path: basename(archivePath),
          contentType: "application/x-tar",
          contentLength: archiveStat.size,
        },
        kind: "docker_image",
        compression: "none",
      },
    },
    { timeoutInSeconds: 180, maxRetries: 3 },
  );

  if (!prepared.build || prepared.presignedRequests.length === 0) {
    throw new Error("Rivet did not return a build id and upload requests");
  }
  const requests = [...prepared.presignedRequests].sort(
    (left, right) => left.byteOffset - right.byteOffset,
  );
  for (const request of requests) {
    await uploadChunk(
      archivePath,
      request.url,
      request.byteOffset,
      request.contentLength,
    );
  }
  await client.builds.complete(
    prepared.build,
    { project: context.project, environment: context.environment },
    { timeoutInSeconds: 180, maxRetries: 3 },
  );
  await client.builds.patchTags(
    prepared.build,
    {
      project: context.project,
      environment: context.environment,
      body: {
        tags: { name: imageTag, current: "true" },
        exclusiveTags: ["current"],
      },
    },
    { timeoutInSeconds: 60, maxRetries: 3 },
  );
  const verified = await client.builds.get(
    prepared.build,
    { project: context.project, environment: context.environment },
    { timeoutInSeconds: 60, maxRetries: 3 },
  );
  if (verified.build.tags.name !== imageTag || verified.build.tags.current !== "true") {
    throw new Error("Published Rivet build tags could not be verified");
  }
  console.log(JSON.stringify({
    ok: true,
    build_id: prepared.build,
    project: context.project,
    environment: context.environment,
    image_tag: imageTag,
    content_length: archiveStat.size,
  }));
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`RIVET_BUILD_PUBLISH_FAILED: ${message}`);
  process.exit(1);
});