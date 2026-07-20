import { setup } from "rivetkit";
import { gameServer } from "./game-server-actor.js";
import { matchmaker } from "./registry.js";

export const runtimeRegistry = setup({
  use: {
    matchmaker,
    gameServer,
  },
  maxIncomingMessageSize: 1_048_576,
  maxOutgoingMessageSize: 10_485_760,
});
