import "./server-full-online.js";
import { runStartupCanary } from "./startup-canary.js";

setTimeout(() => {
  runStartupCanary().catch((error: unknown) => {
    const message = error instanceof Error ? error.stack ?? error.message : String(error);
    console.error(`RIVET_GAME_ACTOR_CANARY_FAILED: ${message}`);
    process.exitCode = 1;
  });
}, 1_500).unref();
