import { setup } from "rivetkit";
import { controlApi } from "./control-api-actor.js";
import { gameServer } from "./game-server-actor.js";
import { regionProbe } from "./region-probe-actor.js";
import { matchmaker } from "./registry.js";

export const runtimeRegistry = setup({
  use: {
    matchmaker,
    gameServer,
    controlApi,
    regionProbe,
  },
  maxIncomingMessageSize: 1_048_576,
  maxOutgoingMessageSize: 10_485_760,
});
