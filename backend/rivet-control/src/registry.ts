import { actor, setup } from "rivetkit";
import type {
  QueueEntry,
  QueueStatus,
  ServerAssignment,
  SessionTicketConsumeRequest,
  SessionTicketConsumeResult,
  SessionTicketRecord,
  ServerCredentialRecord,
} from "./types.js";

type MatchmakerState = {
  queues: Record<string, QueueEntry[]>;
  assignments: Record<string, ServerAssignment>;
  terminal: Record<string, QueueStatus>;
  sessionTickets: Record<string, SessionTicketRecord>;
  ticketOwners: Record<string, string>;
  activeTicketByPlayer: Record<string, string>;
  serverCredentials: Record<string, ServerCredentialRecord>;
  terminalCreatedAt: Record<string, number>;
};

function getQueue(state: MatchmakerState, regionId: string): QueueEntry[] {
  state.queues[regionId] ??= [];
  return state.queues[regionId]!;
}
function ensureIndexes(state: MatchmakerState): void {
  state.ticketOwners ??= {};
  state.activeTicketByPlayer ??= {};
  state.serverCredentials ??= {};
  state.terminalCreatedAt ??= {};
}
function readStatus(state: MatchmakerState, queueTicketId: string): QueueStatus {
  const assignment = state.assignments[queueTicketId];
  if (assignment) return { status: "assigned", queue_ticket_id: queueTicketId, assignment };
  const terminal = state.terminal[queueTicketId];
  if (terminal) return terminal;
  for (const queue of Object.values(state.queues)) {
    const position = queue.findIndex((entry) => entry.queueTicketId === queueTicketId);
    if (position >= 0) return { status: "queued", queue_ticket_id: queueTicketId, position };
  }
  return { status: "expired", queue_ticket_id: queueTicketId, message: "Queue ticket was not found" };
}

export const matchmaker = actor({
  state: {
    queues: {}, assignments: {}, terminal: {}, sessionTickets: {}, ticketOwners: {},
    activeTicketByPlayer: {}, serverCredentials: {}, terminalCreatedAt: {},
  } as MatchmakerState,
  actions: {
    join: (c, regionId: string, entry: QueueEntry): QueueStatus => {
      ensureIndexes(c.state);
      const activeTicket = c.state.activeTicketByPlayer[entry.playerId];
      if (activeTicket) {
        const activeStatus = readStatus(c.state, activeTicket);
        if (activeStatus.status === "queued" || activeStatus.status === "assigned") return activeStatus;
        delete c.state.activeTicketByPlayer[entry.playerId];
      }
      const queue = getQueue(c.state, regionId);
      const existingIndex = queue.findIndex((candidate) => candidate.playerId === entry.playerId);
      if (existingIndex >= 0) {
        const queued = queue[existingIndex]!;
        queued.lastHeartbeatAt = Date.now();
        queued.regionPreference = entry.regionPreference;
        c.state.ticketOwners[queued.queueTicketId] = queued.playerId;
        c.state.activeTicketByPlayer[queued.playerId] = queued.queueTicketId;
        return { status: "queued", queue_ticket_id: queued.queueTicketId, position: existingIndex };
      }
      queue.push(entry);
      c.state.ticketOwners[entry.queueTicketId] = entry.playerId;
      c.state.activeTicketByPlayer[entry.playerId] = entry.queueTicketId;
      return { status: "queued", queue_ticket_id: entry.queueTicketId, position: queue.length - 1 };
    },
    isTicketOwner: (c, queueTicketId: string, playerId: string): boolean => {
      ensureIndexes(c.state);
      return c.state.ticketOwners[queueTicketId] === playerId;
    },
    getStatus: (c, queueTicketId: string): QueueStatus => readStatus(c.state, queueTicketId),
    cancel: (c, queueTicketId: string): QueueStatus => {
      ensureIndexes(c.state);
      const owner = c.state.ticketOwners[queueTicketId];
      if (owner && c.state.activeTicketByPlayer[owner] === queueTicketId) {
        delete c.state.activeTicketByPlayer[owner];
      }
      for (const [regionId, queue] of Object.entries(c.state.queues)) {
        c.state.queues[regionId] = queue.filter((candidate) => candidate.queueTicketId !== queueTicketId);
      }
      delete c.state.assignments[queueTicketId];
      for (const [ticketHash, record] of Object.entries(c.state.sessionTickets)) {
        if (record.queueTicketId === queueTicketId) delete c.state.sessionTickets[ticketHash];
      }
      delete c.state.ticketOwners[queueTicketId];
      const status: QueueStatus = {
        status: "cancelled", queue_ticket_id: queueTicketId, message: "Matchmaking was cancelled",
      };
      c.state.terminal[queueTicketId] = status;
      c.state.terminalCreatedAt[queueTicketId] = Date.now();
      return status;
    },
    takeCandidates: (c, regionId: string, count: number): QueueEntry[] => {
      const queue = getQueue(c.state, regionId);
      return queue.splice(0, Math.max(0, Math.min(count, queue.length)));
    },
    restoreCandidates: (c, regionId: string, entries: QueueEntry[]): void => {
      const queue = getQueue(c.state, regionId);
      const existingPlayers = new Set(queue.map((entry) => entry.playerId));
      for (const entry of entries.reverse()) if (!existingPlayers.has(entry.playerId)) queue.unshift(entry);
    },
    assign: (
      c,
      queueTicketIds: string[],
      assignment: Omit<ServerAssignment, "joinTicket">,
      joinTickets: Record<string, string>,
    ): void => {
      for (const queueTicketId of queueTicketIds) {
        c.state.assignments[queueTicketId] = { ...assignment, joinTicket: joinTickets[queueTicketId] ?? "" };
      }
    },
    registerServerCredential: (c, record: ServerCredentialRecord): void => {
      ensureIndexes(c.state);
      c.state.serverCredentials[record.serverId] = record;
    },
    authorizeServer: (
      c,
      serverId: string,
      matchId: string,
      tokenHash: string,
      now: number,
      consumeResult: boolean = false,
    ): boolean => {
      ensureIndexes(c.state);
      const record = c.state.serverCredentials[serverId];
      if (!record) return false;
      if (record.expiresAt <= now) {
        delete c.state.serverCredentials[serverId];
        return false;
      }
      if (record.matchId !== matchId || record.tokenHash !== tokenHash) return false;
      if (consumeResult) {
        if (record.resultRecordedAt > 0) return false;
        record.resultRecordedAt = now;
      }
      return true;
    },
    registerSessionTickets: (c, records: SessionTicketRecord[]): void => {
      for (const record of records) c.state.sessionTickets[record.ticketHash] = record;
    },
    consumeSessionTicket: (
      c,
      request: SessionTicketConsumeRequest,
    ): SessionTicketConsumeResult => {
      const record = c.state.sessionTickets[request.ticketHash];
      if (!record) return { ok: false, error: "join_ticket_not_found" };
      if (record.consumedAt > 0) return { ok: false, error: "join_ticket_already_used" };
      if (request.now >= record.expiresAt) {
        delete c.state.sessionTickets[request.ticketHash];
        return { ok: false, error: "join_ticket_expired" };
      }
      if (
        record.playerId !== request.playerId || record.matchId !== request.matchId ||
        record.serverId !== request.serverId || record.buildId !== request.buildId ||
        record.protocolVersion !== request.protocolVersion
      ) return { ok: false, error: "join_ticket_claim_mismatch" };
      record.consumedAt = request.now;
      return {
        ok: true, playerId: record.playerId, displayName: record.displayName,
        matchId: record.matchId, serverId: record.serverId,
      };
    },
    releaseMatch: (c, matchId: string, now: number): number => {
      ensureIndexes(c.state);
      let released = 0;
      for (const [queueTicketId, assignment] of Object.entries(c.state.assignments)) {
        if (assignment.matchId !== matchId) continue;
        const owner = c.state.ticketOwners[queueTicketId];
        if (owner && c.state.activeTicketByPlayer[owner] === queueTicketId) {
          delete c.state.activeTicketByPlayer[owner];
        }
        delete c.state.assignments[queueTicketId];
        delete c.state.ticketOwners[queueTicketId];
        c.state.terminal[queueTicketId] = {
          status: "expired", queue_ticket_id: queueTicketId, message: "Match lifecycle completed",
        };
        c.state.terminalCreatedAt[queueTicketId] = now;
        released += 1;
      }
      for (const [ticketHash, record] of Object.entries(c.state.sessionTickets)) {
        if (record.matchId === matchId) delete c.state.sessionTickets[ticketHash];
      }
      for (const [serverId, record] of Object.entries(c.state.serverCredentials)) {
        if (record.matchId === matchId) delete c.state.serverCredentials[serverId];
      }
      return released;
    },
    expireStale: (c, cutoffEpochMs: number): number => {
      ensureIndexes(c.state);
      let expired = 0;
      for (const [regionId, queue] of Object.entries(c.state.queues)) {
        const retained: QueueEntry[] = [];
        for (const entry of queue) {
          if (entry.lastHeartbeatAt >= cutoffEpochMs) {
            retained.push(entry);
            continue;
          }
          expired += 1;
          if (c.state.activeTicketByPlayer[entry.playerId] === entry.queueTicketId) {
            delete c.state.activeTicketByPlayer[entry.playerId];
          }
          c.state.terminal[entry.queueTicketId] = {
            status: "expired", queue_ticket_id: entry.queueTicketId, message: "Queue heartbeat expired",
          };
          c.state.terminalCreatedAt[entry.queueTicketId] = Date.now();
          delete c.state.ticketOwners[entry.queueTicketId];
        }
        c.state.queues[regionId] = retained;
      }
      const now = Date.now();
      for (const [ticketHash, record] of Object.entries(c.state.sessionTickets)) {
        if (record.expiresAt < now - 60_000) delete c.state.sessionTickets[ticketHash];
      }
      for (const [serverId, record] of Object.entries(c.state.serverCredentials)) {
        if (record.expiresAt < now) delete c.state.serverCredentials[serverId];
      }
      const assignmentRetentionMs = 30 * 60 * 1000;
      for (const [queueTicketId, assignment] of Object.entries(c.state.assignments)) {
        if (assignment.expiresAt + assignmentRetentionMs >= now) continue;
        const owner = c.state.ticketOwners[queueTicketId];
        if (owner && c.state.activeTicketByPlayer[owner] === queueTicketId) {
          delete c.state.activeTicketByPlayer[owner];
        }
        delete c.state.assignments[queueTicketId];
        delete c.state.ticketOwners[queueTicketId];
        c.state.terminal[queueTicketId] = {
          status: "expired", queue_ticket_id: queueTicketId, message: "Assigned match reservation expired",
        };
        c.state.terminalCreatedAt[queueTicketId] = now;
        expired += 1;
      }
      const terminalRetentionMs = 60 * 60 * 1000;
      for (const [queueTicketId, createdAt] of Object.entries(c.state.terminalCreatedAt)) {
        if (createdAt + terminalRetentionMs >= now) continue;
        delete c.state.terminalCreatedAt[queueTicketId];
        delete c.state.terminal[queueTicketId];
      }
      return expired;
    },
    heartbeat: (c, queueTicketId: string): QueueStatus => {
      for (const queue of Object.values(c.state.queues)) {
        const entry = queue.find((candidate) => candidate.queueTicketId === queueTicketId);
        if (entry) entry.lastHeartbeatAt = Date.now();
      }
      return readStatus(c.state, queueTicketId);
    },
    queueSize: (c, regionId: string): number => getQueue(c.state, regionId).length,
  },
});

export const registry = setup({ use: { matchmaker } });
