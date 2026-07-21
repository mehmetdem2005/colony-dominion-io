import assert from "node:assert/strict";
import { evaluateMatchmakingWindow } from "../src/matchmaking-policy.js";

const base = {
  oldestJoinedAt: 1_000,
  minimumHumanPlayers: 1,
  targetPlayers: 10,
  botBackfillWaitMs: 30_000,
};

const waiting = evaluateMatchmakingWindow({ ...base, queueSize: 1, now: 20_000 });
assert.equal(waiting.allocate, false);
assert.equal(waiting.reason, "waiting");
assert.equal(waiting.waitRemainingMs, 11_000);

const backfilled = evaluateMatchmakingWindow({ ...base, queueSize: 1, now: 31_000 });
assert.equal(backfilled.allocate, true);
assert.equal(backfilled.reason, "bot_backfill");
assert.equal(backfilled.humanPlayers, 1);
assert.equal(backfilled.botPlayers, 9);
assert.equal(backfilled.ranked, false);

const full = evaluateMatchmakingWindow({ ...base, queueSize: 10, now: 2_000 });
assert.equal(full.allocate, true);
assert.equal(full.reason, "full_human_lobby");
assert.equal(full.botPlayers, 0);
assert.equal(full.ranked, true);

const minimum = evaluateMatchmakingWindow({
  ...base,
  queueSize: 1,
  minimumHumanPlayers: 2,
  now: 90_000,
});
assert.equal(minimum.allocate, false);
assert.equal(minimum.reason, "minimum_humans");

console.log("PASS matchmaking-policy.test");
