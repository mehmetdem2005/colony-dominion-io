import type { RegionDefinition } from "./types.js";

const fallbackRegions: RegionDefinition[] = [
  {
    id: "eu",
    displayName: "Avrupa — Frankfurt",
    shortName: "EU-FRA",
    probeUrl: "",
    enabled: true,
    providerRegion: "fra",
  },
];

export function loadRegions(): RegionDefinition[] {
  const raw = process.env.REGIONS_JSON;
  if (!raw) return fallbackRegions.filter((region) => region.enabled);
  try {
    const parsed = JSON.parse(raw) as RegionDefinition[];
    const normalized = parsed.filter(
      (region) => region.id && region.displayName && region.enabled,
    );
    return normalized.length > 0 ? normalized : fallbackRegions;
  } catch {
    return fallbackRegions;
  }
}

export function findRegion(
  regions: RegionDefinition[],
  regionId: string,
): RegionDefinition {
  return regions.find((region) => region.id === regionId) ?? regions[0]!;
}
