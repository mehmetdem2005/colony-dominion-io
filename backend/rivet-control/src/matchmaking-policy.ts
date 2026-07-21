export type MatchmakingWindowInput = {
  queueSize: number;
  oldestJoinedAt: number;
  now: number;
  minimumHumanPlayers: number;
  targetPlayers: number;
  botBackfillWaitMs: number;
};

export type MatchmakingWindowDecision = {
  allocate: boolean;
  reason: "empty" | "minimum_humans" | "waiting" | "full_human_lobby" | "bot_backfill";
  humanPlayers: number;
  botPlayers: number;
  backfillAt: number;
  waitRemainingMs: number;
  ranked: boolean;
};

function boundedInteger(value: number, minimum: number, maximum: number): number {
  if (!Number.isFinite(value)) return minimum;
  return Math.max(minimum, Math.min(maximum, Math.trunc(value)));
}

export function evaluateMatchmakingWindow(input: MatchmakingWindowInput): MatchmakingWindowDecision {
  const targetPlayers = boundedInteger(input.targetPlayers, 1, 10);
  const minimumHumanPlayers = boundedInteger(input.minimumHumanPlayers, 1, targetPlayers);
  const humanPlayers = boundedInteger(input.queueSize, 0, targetPlayers);
  const oldestJoinedAt = Math.max(0, Math.trunc(input.oldestJoinedAt));
  const now = Math.max(0, Math.trunc(input.now));
  const waitMs = boundedInteger(input.botBackfillWaitMs, 5_000, 120_000);
  const backfillAt = oldestJoinedAt > 0 ? oldestJoinedAt + waitMs : now + waitMs;
  const waitRemainingMs = Math.max(0, backfillAt - now);
  const botPlayers = Math.max(0, targetPlayers - humanPlayers);

  if (humanPlayers <= 0) {
    return {
      allocate: false,
      reason: "empty",
      humanPlayers,
      botPlayers: targetPlayers,
      backfillAt,
      waitRemainingMs,
      ranked: false,
    };
  }
  if (humanPlayers >= targetPlayers) {
    return {
      allocate: true,
      reason: "full_human_lobby",
      humanPlayers: targetPlayers,
      botPlayers: 0,
      backfillAt,
      waitRemainingMs: 0,
      ranked: true,
    };
  }
  if (humanPlayers < minimumHumanPlayers) {
    return {
      allocate: false,
      reason: "minimum_humans",
      humanPlayers,
      botPlayers,
      backfillAt,
      waitRemainingMs,
      ranked: false,
    };
  }
  if (waitRemainingMs > 0) {
    return {
      allocate: false,
      reason: "waiting",
      humanPlayers,
      botPlayers,
      backfillAt,
      waitRemainingMs,
      ranked: false,
    };
  }
  return {
    allocate: true,
    reason: "bot_backfill",
    humanPlayers,
    botPlayers,
    backfillAt,
    waitRemainingMs: 0,
    ranked: botPlayers === 0,
  };
}
