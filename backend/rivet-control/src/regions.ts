import type { RegionDefinition } from "./types.js";

const DEPLOYED_PROVIDER_REGION = "fra";

const fallbackRegions: RegionDefinition[] = [
  {
    id: "eu",
    displayName: "Avrupa — Frankfurt",
    shortName: "EU-FRA",
    probeUrl: "",
    enabled: true,
    providerRegion: DEPLOYED_PROVIDER_REGION,
  },
];

function appendPathBeforeQuery(baseUrl: string, pathSuffix: string): string {
  const url = new URL(baseUrl);
  url.hash = "";
  url.pathname = `${url.pathname.replace(/\/$/, "")}/${pathSuffix.replace(/^\//, "")}`;
  return url.toString();
}

function withPublicProbe(regions: RegionDefinition[]): RegionDefinition[] {
  const publicBase = process.env.PUBLIC_CONTROL_BASE_URL?.trim() ?? "";
  return regions
    .filter((region) => region.enabled)
    .map((region) => ({
      ...region,
      probeUrl:
        region.probeUrl ||
        (publicBase ? appendPathBeforeQuery(publicBase, "/v1/health/ping") : ""),
    }));
}

export function loadRegions(): RegionDefinition[] {
  const raw = process.env.REGIONS_JSON;
  if (!raw) return withPublicProbe(fallbackRegions);
  try {
    const parsed = JSON.parse(raw) as RegionDefinition[];
    const normalized = parsed.filter(
      (region) => region.id && region.displayName && region.enabled,
    );
    return withPublicProbe(normalized.length > 0 ? normalized : fallbackRegions);
  } catch {
    return withPublicProbe(fallbackRegions);
  }
}

export function findRegion(
  regions: RegionDefinition[],
  regionId: string,
): RegionDefinition {
  return regions.find((region) => region.id === regionId) ?? regions[0]!;
}
