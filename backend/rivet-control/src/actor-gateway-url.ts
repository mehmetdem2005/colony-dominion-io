/** Inserts an actor request path without dropping Rivet's routing query. */
export function composeActorRequestUrl(rawGatewayUrl: string, requestPath = ""): string {
  const gatewayUrl = new URL(rawGatewayUrl);
  gatewayUrl.hash = "";
  const gatewayQuery = gatewayUrl.search;
  gatewayUrl.search = "";
  const suffix = requestPath.replace(/^\/+/, "");
  gatewayUrl.pathname = `${gatewayUrl.pathname.replace(/\/$/, "")}/request${
    suffix ? `/${suffix}` : ""
  }`;
  return `${gatewayUrl.toString().replace(/\/$/, "")}${gatewayQuery}`;
}
