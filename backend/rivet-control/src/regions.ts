import type { RegionDefinition } from "./types.js";

const fallbackRegions: RegionDefinition[] = [
  { id: "eu", displayName: "Avrupa", shortName: "EU", probeUrl: "", enabled: true, providerRegion: "fra" },
  { id: "na-east", displayName: "Kuzey Amerika Doğu", shortName: "NA-E", probeUrl: "", enabled: false, providerRegion: "iad" },
  { id: "na-west", displayName: "Kuzey Amerika Batı", shortName: "NA-W", probeUrl: "", enabled: false, providerRegion: "lax" },
  { id: "sa", displayName: "Güney Amerika", shortName: "SA", probeUrl: "", enabled: false, providerRegion: "gru" },
  { id: "asia", displayName: "Asya", shortName: "ASIA", probeUrl: "", enabled: false, providerRegion: "sin" },
  { id: "oceania", displayName: "Okyanusya", shortName: "OCE", probeUrl: "", enabled: false, providerRegion: "syd" },
  { id: "africa", displayName: "Afrika", shortName: "AF", probeUrl: "", enabled: false },
];

function withPublicProbe(regions: RegionDefinition[]): RegionDefinition[] {
  const publicBase = process.env.PUBLIC_CONTROL_BASE_URL?.replace(/\/$/, "");
  return regions.map((region) => ({
    ...region,
    probeUrl:
      region.probeUrl ||
      (publicBase ? `${publicBase}/v1/health/ping?region=${encodeURIComponent(region.id)}` : ""),
  }));
}

export function loadRegions(): RegionDefinition[] {
  const raw = process.env.REGIONS_JSON;
  if (!raw) return withPublicProbe(fallbackRegions);
  try {
    const parsed = JSON.parse(raw) as RegionDefinition[];
    return withPublicProbe(parsed.filter((region) => region.id && region.displayName));
  } catch {
    return withPublicProbe(fallbackRegions);
  }
}

export function findRegion(regions: RegionDefinition[], regionId: string): RegionDefinition {
  return regions.find((region) => region.id === regionId) ?? regions[0]!;
}
