import "./server-full-online.js";
import { runStartupCanary } from "./startup-canary.js";

setTimeout(() => {
  runStartupCanary().catch((error: unknown) => {
    const message = error instanceof Error ? error.stack ?? error.message : String(error);
    console.error(`RIVET_GAME_ACTOR_CANARY_FAILED: ${message}`);
    setTimeout(() => process.exit(1), 250).unref();
  });
}, 1_500).unref();
