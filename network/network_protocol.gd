class_name NetworkProtocol
extends RefCounted

const VERSION: int = 3
const CHANNEL_CONTROL: int = 0
const CHANNEL_SNAPSHOT: int = 1
const CHANNEL_INPUT: int = 2
const CHANNEL_TELEMETRY: int = 3

const SNAPSHOT_HZ: float = 20.0
const INPUT_HZ: float = 30.0
const PING_INTERVAL_SECONDS: float = 1.0
const PING_TIMEOUT_SECONDS: float = 3.0
const AUTH_TIMEOUT_SECONDS: float = 10.0
const RECONNECT_GRACE_SECONDS: float = 60.0
const RECONNECT_RETRY_SECONDS: float = 1.25
const RECONNECT_PERSIST_REFRESH_SECONDS: float = 4.0
const RECONNECT_PERSIST_TTL_SECONDS: float = 75.0
const INTERPOLATION_DELAY_MSEC: int = 110
const MAX_SNAPSHOT_ENTITIES: int = 128
const SERVER_JOIN_TIMEOUT_SECONDS: float = 90.0
const SERVER_START_WAIT_SECONDS: float = 5.0

const DEFAULT_GAME_PORT: int = 7000
const DEFAULT_CONTROL_PORT: int = 7001
const DEFAULT_MAX_PLAYERS: int = 10
const UNAUTHENTICATED_CONNECTION_HEADROOM: int = 8
const ENET_CHANNEL_COUNT: int = 4

const SERVER_PEER_ID: int = 1


static func normalize_assignment(value: Dictionary) -> Dictionary:
	return {
		"match_id": String(value.get("match_id", "")).strip_edges(),
		"server_id": String(value.get("server_id", "")).strip_edges(),
		"host": String(value.get("host", "")).strip_edges(),
		"port": clampi(int(value.get("port", 0)), 0, 65535),
		"join_ticket": String(value.get("join_ticket", "")).strip_edges(),
		"region_id": String(value.get("region_id", "")).strip_edges(),
		"region_name": String(value.get("region_name", "")).strip_edges(),
		"region_short_name": String(value.get("region_short_name", "")).strip_edges(),
		"expires_at": int(value.get("expires_at", 0)),
		"protocol_version": int(value.get("protocol_version", 0)),
	}


static func validate_reconnect_assignment(value: Dictionary) -> Dictionary:
	var assignment: Dictionary = normalize_assignment(value)
	if String(assignment.get("match_id", "")).is_empty():
		return {"ok": false, "error": "Maç kimliği eksik"}
	if String(assignment.get("server_id", "")).is_empty():
		return {"ok": false, "error": "Sunucu kimliği eksik"}
	if String(assignment.get("host", "")).is_empty():
		return {"ok": false, "error": "Sunucu adresi eksik"}
	if int(assignment.get("port", 0)) <= 0:
		return {"ok": false, "error": "Sunucu portu geçersiz"}
	if int(assignment.get("protocol_version", 0)) != VERSION:
		return {"ok": false, "error": "Ağ protokol sürümü uyumsuz"}
	return {"ok": true, "assignment": assignment}


static func validate_assignment(value: Dictionary) -> Dictionary:
	var assignment: Dictionary = normalize_assignment(value)
	if String(assignment.get("match_id", "")).is_empty():
		return {"ok": false, "error": "Maç kimliği eksik"}
	if String(assignment.get("server_id", "")).is_empty():
		return {"ok": false, "error": "Sunucu kimliği eksik"}
	if String(assignment.get("host", "")).is_empty():
		return {"ok": false, "error": "Sunucu adresi eksik"}
	if int(assignment.get("port", 0)) <= 0:
		return {"ok": false, "error": "Sunucu portu geçersiz"}
	var join_ticket: String = String(assignment.get("join_ticket", ""))
	if join_ticket.length() < 16 or join_ticket.length() > 256:
		return {"ok": false, "error": "Bağlantı bileti geçersiz"}
	if int(assignment.get("protocol_version", 0)) != VERSION:
		return {"ok": false, "error": "Ağ protokol sürümü uyumsuz"}
	if int(assignment.get("expires_at", 0)) <= int(Time.get_unix_time_from_system() * 1000.0):
		return {"ok": false, "error": "Sunucu atamasının süresi doldu"}
	return {"ok": true, "assignment": assignment}


static func make_command(
	sequence: int, client_tick: int, command_type: StringName, payload: Dictionary
) -> Dictionary:
	return {
		"sequence": maxi(sequence, 0),
		"client_tick": maxi(client_tick, 0),
		"type": command_type,
		"payload": payload.duplicate(true),
	}
