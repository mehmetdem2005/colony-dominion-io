import { open, stat } from "node:fs/promises";
import { basename, resolve } from "node:path";
import { RivetClient } from "@rivet-gg/api";

function requireEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
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
  const project = requireEnv("RIVET_PROJECT");
  const environment = requireEnv("RIVET_ENVIRONMENT");
  const imageTag = requireEnv("RIVET_GAME_SERVER_BUILD_TAG");
  const archivePath = resolve(requireEnv("RIVET_BUILD_ARCHIVE"));
  const archiveStat = await stat(archivePath);
  if (!archiveStat.isFile() || archiveStat.size <= 0) {
    throw new Error("RIVET_BUILD_ARCHIVE must point to a non-empty docker-save tar archive");
  }

  const client = new RivetClient({ token });
  const prepared = await client.builds.prepare(
    {
      project,
      environment,
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
    { project, environment },
    { timeoutInSeconds: 180, maxRetries: 3 },
  );
  await client.builds.patchTags(
    prepared.build,
    {
      project,
      environment,
      body: {
        tags: { name: imageTag, current: "true" },
        exclusiveTags: ["current"],
      },
    },
    { timeoutInSeconds: 60, maxRetries: 3 },
  );
  const verified = await client.builds.get(
    prepared.build,
    { project, environment },
    { timeoutInSeconds: 60, maxRetries: 3 },
  );
  if (verified.build.tags.name !== imageTag || verified.build.tags.current !== "true") {
    throw new Error("Published Rivet build tags could not be verified");
  }
  console.log(JSON.stringify({
    ok: true,
    build_id: prepared.build,
    image_tag: imageTag,
    content_length: archiveStat.size,
  }));
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`RIVET_BUILD_PUBLISH_FAILED: ${message}`);
  process.exit(1);
});
