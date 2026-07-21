import "./server-full-online.js";
import { ensurePublicControlGateway } from "./public-control-gateway.js";
import { runStartupCanary } from "./startup-canary.js";

setTimeout(() => {
  (async () => {
    await ensurePublicControlGateway();
    await runStartupCanary();
  })().catch((error: unknown) => {
    const message = error instanceof Error ? error.stack ?? error.message : String(error);
    console.error(`RIVET_FULL_ONLINE_BOOTSTRAP_FAILED: ${message}`);
    setTimeout(() => process.exit(1), 250).unref();
  });
}, 1_500).unref();
