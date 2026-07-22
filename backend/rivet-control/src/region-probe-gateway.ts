import { createClient } from "rivetkit/client";
import { composeActorRequestUrl } from "./actor-gateway-url.js";
import { registerRegionProbeUrl } from "./region-probe-directory.js";
import { runtimeRegistry } from "./runtime-registry.js";
import type { RegionDefinition } from "./types.js";

function actorKey(region: RegionDefinition): string {
  const providerRegion = region.providerRegion ?? region.id;
  return `region-probe-${region.id}-${providerRegion}-v1`;
}

export async function ensureRegionProbeGateways(
  regions: RegionDefinition[],
): Promise<Record<string, string>> {
  const port = Number(process.env.RIVET_PORT ?? process.env.PORT ?? 3000);
  const internalBaseUrl = process.env.INTERNAL_BASE_URL ?? `http://127.0.0.1:${port}`;
  const client = createClient<typeof runtimeRegistry>(
    `${internalBaseUrl.replace(/\/$/, "")}/api/rivet`,
  );
  const resolved: Record<string, string> = {};

  for (const region of regions.filter((candidate) => candidate.enabled)) {
    const providerRegion = region.providerRegion?.trim() || region.id;
    const key = actorKey(region);
    const handle = await client.regionProbe.getOrCreate([key], {
      createWithInput: { regionId: region.id, providerRegion },
      createInRegion: providerRegion,
    });
    const metadata = await handle.metadata();
    if (
      metadata.ok !== true ||
      metadata.regionId !== region.id ||
      metadata.providerRegion !== providerRegion
    ) {
      throw new Error(`Region probe actor metadata mismatch for ${region.id}`);
    }
    const rawGatewayUrl = await handle.getGatewayUrl();
    const probeUrl = composeActorRequestUrl(rawGatewayUrl, "/v1/ping");
    if (process.env.NODE_ENV === "production" && !probeUrl.startsWith("https://")) {
      throw new Error(`Region probe gateway must use HTTPS: ${region.id}`);
    }
    registerRegionProbeUrl(region.id, probeUrl);
    resolved[region.id] = probeUrl;
    console.log(
      JSON.stringify({
        marker: "RIVET_REGION_PROBE_READY",
        region_id: region.id,
        provider_region: providerRegion,
        actor_key: key,
        probe_url: probeUrl,
      }),
    );
  }
  return resolved;
}
