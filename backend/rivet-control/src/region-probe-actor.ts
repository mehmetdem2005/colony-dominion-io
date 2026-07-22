import { actor } from "rivetkit";

export type RegionProbeActorInput = {
  regionId: string;
  providerRegion: string;
};

type RegionProbeActorState = RegionProbeActorInput & {
  startedAt: number;
};

function requireSlug(value: string, name: string): string {
  const cleaned = value.trim().toLowerCase();
  if (!/^[a-z0-9-]{2,32}$/.test(cleaned)) {
    throw new Error(`${name} must be a lowercase region slug`);
  }
  return cleaned;
}

/**
 * A direct, dependency-free latency target. Unlike the control actor it never
 * proxies into the Node service, authenticates a user, or touches actor state.
 */
export const regionProbe = actor({
  createState: (_c, input: RegionProbeActorInput): RegionProbeActorState => ({
    regionId: requireSlug(input.regionId, "regionId"),
    providerRegion: requireSlug(input.providerRegion, "providerRegion"),
    startedAt: Date.now(),
  }),
  options: {
    name: "Colony Region Latency Probe",
    sleepTimeout: 4 * 60 * 60 * 1_000,
    actionTimeout: 5_000,
  },
  onRequest: (c, request): Response => {
    const pathname = new URL(request.url).pathname.replace(/\/$/, "");
    if (request.method !== "GET" || !pathname.endsWith("/v1/ping")) {
      return Response.json({ error: "not_found" }, { status: 404 });
    }
    return Response.json(
      {
        ok: true,
        scope: "region-probe",
        region: c.state.regionId,
        provider_region: c.state.providerRegion,
        now: Date.now(),
      },
      {
        headers: {
          "cache-control": "no-store, max-age=0",
          "x-content-type-options": "nosniff",
          "timing-allow-origin": "*",
        },
      },
    );
  },
  actions: {
    metadata: (c) => ({ ...c.state, ok: true }),
  },
});
