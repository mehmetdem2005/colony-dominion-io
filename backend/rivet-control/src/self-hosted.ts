import { registry } from "./registry.js";

registry.startEnvoy();
await import("./server.js");
