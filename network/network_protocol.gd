class_name NetworkProtocol
extends RefCounted

const VERSION: int = 4
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

const TRANSPORT_ENET: String = "enet"
const TRANSPORT_WEBSOCKET: String = "websocket"
const SERVER_PEER_ID: int = 1


static func normalize_assignment(value: Dictionary) -> Dictionary:
	var transport: String = String(value.get("transport", TRANSPORT_ENET)).strip_edges().to_lower()
	return {
		"match_id": String(value.get("match_id", "")).strip_edges(),
		"server_id": String(value.get("server_id", "")).strip_edges(),
		"transport": transport,
		"websocket_url": String(value.get("websocket_url", "")).strip_edges(),
		"host": String(value.get("host", "")).strip_edges(),
		"port": clampi(int(value.get("port", 0)), 0, 65535),
		"join_ticket": String(value.get("join_ticket", "")).strip_edges(),
		"region_id": String(value.get("region_id", "")).strip_edges(),
		"region_name": String(value.get("region_name", "")).strip_edges(),
		"region_short_name": String(value.get("region_short_name", "")).strip_edges(),
		"expires_at": int(value.get("expires_at", 0)),
		"protocol_version": int(value.get("protocol_version", 0)),
		"human_players": clampi(int(value.get("human_players", 1)), 1, DEFAULT_MAX_PLAYERS),
		"bot_players": clampi(int(value.get("bot_players", 0)), 0, DEFAULT_MAX_PLAYERS),
		"ranked": bool(value.get("ranked", false)),
	}


static func validate_reconnect_assignment(value: Dictionary) -> Dictionary:
	var assignment: Dictionary = normalize_assignment(value)
	var common_error: String = _validate_assignment_endpoint(assignment)
	if not common_error.is_empty():
		return {"ok": false, "error": common_error}
	if int(assignment.get("protocol_version", 0)) != VERSION:
		return {"ok": false, "error": "Ağ protokol sürümü uyumsuz"}
	return {"ok": true, "assignment": assignment}


static func validate_assignment(value: Dictionary) -> Dictionary:
	var assignment: Dictionary = normalize_assignment(value)
	var common_error: String = _validate_assignment_endpoint(assignment)
	if not common_error.is_empty():
		return {"ok": false, "error": common_error}
	var join_ticket: String = String(assignment.get("join_ticket", ""))
	if join_ticket.length() < 16 or join_ticket.length() > 256:
		return {"ok": false, "error": "Bağlantı bileti geçersiz"}
	if int(assignment.get("protocol_version", 0)) != VERSION:
		return {"ok": false, "error": "Ağ protokol sürümü uyumsuz"}
	var human_players := int(assignment.get("human_players", 0))
	var bot_players := int(assignment.get("bot_players", 0))
	if human_players < 1 or human_players + bot_players != DEFAULT_MAX_PLAYERS:
		return {"ok": false, "error": "Maç oyuncu dağılımı geçersiz"}
	if bool(assignment.get("ranked", false)) and bot_players > 0:
		return {"ok": false, "error": "Bot içeren maç dereceli olamaz"}
	if int(assignment.get("expires_at", 0)) <= int(Time.get_unix_time_from_system() * 1000.0):
		return {"ok": false, "error": "Sunucu atamasının süresi doldu"}
	return {"ok": true, "assignment": assignment}


static func _validate_assignment_endpoint(assignment: Dictionary) -> String:
	if String(assignment.get("match_id", "")).is_empty():
		return "Maç kimliği eksik"
	if String(assignment.get("server_id", "")).is_empty():
		return "Sunucu kimliği eksik"
	var transport: String = String(assignment.get("transport", TRANSPORT_ENET))
	if transport == TRANSPORT_WEBSOCKET:
		var websocket_url: String = String(assignment.get("websocket_url", ""))
		if (
			not websocket_url.begins_with("wss://")
			and not (OS.is_debug_build() and websocket_url.begins_with("ws://"))
		):
			return "Rivet WebSocket adresi geçersiz"
		return ""
	if transport != TRANSPORT_ENET:
		return "Desteklenmeyen ağ taşıma türü"
	if String(assignment.get("host", "")).is_empty():
		return "Sunucu adresi eksik"
	if int(assignment.get("port", 0)) <= 0:
		return "Sunucu portu geçersiz"
	return ""


static func make_command(
	sequence: int, client_tick: int, command_type: StringName, payload: Dictionary
) -> Dictionary:
	return {
		"sequence": maxi(sequence, 0),
		"client_tick": maxi(client_tick, 0),
		"type": command_type,
		"payload": payload.duplicate(true),
	}
