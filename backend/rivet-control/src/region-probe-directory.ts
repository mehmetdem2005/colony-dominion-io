const resolvedProbeUrls = new Map<string, string>();

export function registerRegionProbeUrl(regionId: string, probeUrl: string): void {
  resolvedProbeUrls.set(regionId, probeUrl);
}

export function resolveRegionProbeUrl(regionId: string, configuredUrl = ""): string {
  return resolvedProbeUrls.get(regionId) ?? configuredUrl;
}
