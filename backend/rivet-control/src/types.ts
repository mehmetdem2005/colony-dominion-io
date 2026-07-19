export type QueueEntry = {
  queueTicketId: string;
  playerId: string;
  displayName: string;
  regionPreference: string;
  buildId: string;
  protocolVersion: number;
  joinedAt: number;
  lastHeartbeatAt: number;
};

export type ServerAssignment = {
  matchId: string;
  serverId: string;
  host: string;
  port: number;
  joinTicket: string;
  regionId: string;
  regionName: string;
  regionShortName: string;
  expiresAt: number;
  protocolVersion: number;
};

export type SessionTicketRecord = {
  queueTicketId: string;
  ticketHash: string;
  playerId: string;
  displayName: string;
  matchId: string;
  serverId: string;
  buildId: string;
  protocolVersion: number;
  expiresAt: number;
  consumedAt: number;
};

export type SessionTicketConsumeRequest = {
  ticketHash: string;
  playerId: string;
  matchId: string;
  serverId: string;
  buildId: string;
  protocolVersion: number;
  now: number;
};

export type SessionTicketConsumeResult =
  | { ok: true; playerId: string; displayName: string; matchId: string; serverId: string }
  | { ok: false; error: string };

export type ServerCredentialRecord = {
  matchId: string;
  serverId: string;
  tokenHash: string;
  expiresAt: number;
  resultRecordedAt: number;
};

export type QueueStatus =
  | { status: "queued"; queue_ticket_id: string; position: number }
  | { status: "assigned"; queue_ticket_id: string; assignment: ServerAssignment }
  | {
      status: "cancelled" | "expired" | "failed";
      queue_ticket_id: string;
      message: string;
    };

export type RegionDefinition = {
  id: string;
  displayName: string;
  shortName: string;
  probeUrl: string;
  enabled: boolean;
  providerRegion?: string;
};
