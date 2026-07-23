extends Node

# Authentication is intentionally guard-clause based.
# gdlint: disable=max-returns,max-file-lines

signal server_started(port: int)
signal server_start_failed(message: String)
signal client_connected
signal client_authenticated(team_id: int, reconnect_token: String)
signal client_connection_failed(message: String)
signal client_disconnected(message: String)
signal reconnect_started(attempt: int)
signal reconnect_failed(message: String)
signal snapshot_received(snapshot: Dictionary)
signal player_state_received(state: Dictionary)
signal command_acknowledged(sequence: int)
signal server_peer_authenticated(peer_id: int, team_id: int, player_id: String)
signal server_peer_released(peer_id: int, team_id: int)
signal match_ended(winner_name: String)

const PROTOCOL_SCRIPT := preload("res://network/network_protocol.gd")
const HTTP_CLIENT_SCRIPT := preload("res://network/http_json_client.gd")
const HEALTH_SERVER_SCRIPT := preload("res://network/dedicated_server_health.gd")
const RECONNECT_STORE_SCRIPT := preload("res://network/reconnect_session_store.gd")
const MATCH_START_GATE_SCRIPT := preload("res://network/dedicated_match_start_gate.gd")

const SERVER_SHUTDOWN_DELAY_SECONDS: float = 8.0
const MATCH_RESULT_RETRY_COUNT: int = 3

var _peer: ENetMultiplayerPeer = null
var _match: MatchController = null
var _ticket_http: HttpJsonClient = null
var _reconnect_store: ReconnectSessionStore = null
var _is_server: bool = false
var _authenticated: bool = false
var _assignment: Dictionary = {}
var _player_id: String = ""
var _display_name: String = ""
var _build_id: String = ""
var _reconnect_token: String = ""
var _local_team_id: int = -1
var _last_server_tick: int = 0
var _command_sequence: int = 0
var _last_ack_sequence: int = -1
var _server_port: int = NetworkProtocol.DEFAULT_GAME_PORT
var _max_players: int = NetworkProtocol.DEFAULT_MAX_PLAYERS
var _human_player_count: int = 1
var _bot_count: int = NetworkProtocol.DEFAULT_MAX_PLAYERS - 1
var _ranked_match: bool = false
var _server_match_id: String = ""
var _server_id: String = ""
var _server_build_id: String = ""
var _snapshot_left: float = 0.0
var _ping_left: float = 0.0
var _ping_nonce: int = 0
var _pending_pings: Dictionary = {}
var _ping_samples: Array[float] = []
var _sent_ping_count: int = 0
var _lost_ping_count: int = 0
var _reconnect_attempt: int = 0
var _reconnect_deadline_msec: int = 0
var _reconnect_in_progress: bool = false
var _manual_disconnect: bool = false
var _disconnect_flush_in_progress: bool = false
var _peer_records: Dictionary = {}
var _reservations_by_player: Dictionary = {}
var _participant_history: Dictionary = {}
var _auth_deadlines: Dictionary = {}
var _auth_in_progress: Dictionary = {}
var _consumed_join_ticket_hashes: Dictionary = {}
var _health_server: DedicatedServerHealth = null
var _server_started_unix_msec: int = 0
var _match_result_reporting: bool = false
var _last_reconnect_persist_msec: int = 0
var _metric_auth_accepted_total: int = 0
var _metric_auth_rejected_total: int = 0
var _metric_reconnect_success_total: int = 0
var _metric_commands_received_total: int = 0
var _metric_snapshots_sent_total: int = 0
var _metric_match_result_failures_total: int = 0
var _match_start_gate: DedicatedMatchStartGate = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reconnect_store = RECONNECT_STORE_SCRIPT.new() as ReconnectSessionStore
	_match_start_gate = MATCH_START_GATE_SCRIPT.new() as DedicatedMatchStartGate
	_ticket_http = HTTP_CLIENT_SCRIPT.new() as HttpJsonClient
	_ticket_http.name = "JoinTicketHTTP"
	_ticket_http.timeout_seconds = 5.0
	add_child(_ticket_http)
	_connect_multiplayer_signals()
	if DedicatedMatchStartGate.is_server_mode():
		call_deferred("start_dedicated_server")


func _process(delta: float) -> void:
	if _is_server:
		_server_process(delta)
	else:
		_client_process(delta)


func bind_match(match_node: MatchController) -> void:
	_match = match_node
	if (
		DedicatedMatchStartGate.is_server_mode()
		and is_instance_valid(_match)
		and _match_start_gate != null
	):
		_match_start_gate.bind_match(_match, Time.get_ticks_msec())
	if (
		_is_server
		and is_instance_valid(_match)
		and is_instance_valid(_match.events)
		and not _match.events.match_ended.is_connected(_on_server_match_ended)
	):
		_match.events.match_ended.connect(_on_server_match_ended)


func start_dedicated_server() -> Dictionary:
	if _peer != null:
		return {"ok": true, "port": _server_port}
	_is_server = true
	_server_port = DedicatedMatchStartGate.read_int_environment(
		"GAME_PORT", NetworkProtocol.DEFAULT_GAME_PORT, 1, 65535
	)
	_max_players = DedicatedMatchStartGate.read_int_environment(
		"MAX_PLAYERS", NetworkProtocol.DEFAULT_MAX_PLAYERS, 1, 64
	)
	var expected_players: int = DedicatedMatchStartGate.read_int_environment(
		"EXPECTED_PLAYERS", _max_players, 1, _max_players
	)
	var population_error: String = _configure_server_population(expected_players)
	if not population_error.is_empty():
		server_start_failed.emit(population_error)
		push_error(population_error)
		return {"ok": false, "error": population_error}
	if _match_start_gate != null:
		_match_start_gate.set_expected_players(expected_players)
	_server_match_id = OS.get_environment("MATCH_ID").strip_edges()
	_server_id = OS.get_environment("SERVER_ID").strip_edges()
	_server_build_id = OS.get_environment("BUILD_ID").strip_edges()
	_server_started_unix_msec = roundi(Time.get_unix_time_from_system() * 1000.0)
	if _server_build_id.is_empty():
		_server_build_id = "PHASE-05.5-GOOGLE-BOT-BACKFILL"
	if not OS.is_debug_build() and (_server_match_id.is_empty() or _server_id.is_empty()):
		var identity_error := "Dedicated server MATCH_ID/SERVER_ID environment is missing"
		server_start_failed.emit(identity_error)
		push_error(identity_error)
		return {"ok": false, "error": identity_error}
	_peer = ENetMultiplayerPeer.new()
	_peer.set_bind_ip("*")
	var maximum_connections: int = mini(
		_max_players + NetworkProtocol.UNAUTHENTICATED_CONNECTION_HEADROOM, 64
	)
	var error: Error = _peer.create_server(
		_server_port, maximum_connections, NetworkProtocol.ENET_CHANNEL_COUNT
	)
	if error != OK:
		_peer = null
		var message: String = "ENet sunucusu başlatılamadı: %s" % error_string(error)
		server_start_failed.emit(message)
		return {"ok": false, "error": message}
	multiplayer.multiplayer_peer = _peer
	server_started.emit(_server_port)
	print("[GameTransport] ENet server listening on UDP %d" % _server_port)
	_health_server = HEALTH_SERVER_SCRIPT.new() as DedicatedServerHealth
	_health_server.name = "DedicatedServerHealth"
	add_child(_health_server)
	_health_server.configure(self, _get_bound_match)
	_health_server.start(
		DedicatedMatchStartGate.read_int_environment(
			"CONTROL_PORT", NetworkProtocol.DEFAULT_CONTROL_PORT, 1, 65535
		)
	)
	return {"ok": true, "port": _server_port}


func _configure_server_population(expected_players: int) -> String:
	_human_player_count = DedicatedMatchStartGate.read_int_environment(
		"HUMAN_PLAYER_COUNT", expected_players, expected_players, _max_players
	)
	_bot_count = DedicatedMatchStartGate.read_int_environment(
		"BOT_COUNT", _max_players - _human_player_count, 0, _max_players
	)
	_ranked_match = OS.get_environment("RANKED_MATCH") == "1"
	if _human_player_count + _bot_count != _max_players:
		return "Dedicated server human and bot counts must equal MAX_PLAYERS"
	if _ranked_match and _bot_count > 0:
		return "Bot-backfilled matches cannot start as ranked"
	return ""


func connect_to_assignment(
	assignment_value: Dictionary, player_id: String, display_name: String, build_id: String
) -> Dictionary:
	if _is_server:
		return {"ok": false, "error": "Sunucu örneği istemci bağlantısı başlatamaz"}
	var validation: Dictionary = NetworkProtocol.validate_assignment(assignment_value)
	if not bool(validation.get("ok", false)):
		return validation
	_assignment = (validation.get("assignment", {}) as Dictionary).duplicate(true)
	if _reconnect_store != null:
		_reconnect_store.clear()
	_reconnect_token = ""
	_player_id = player_id.strip_edges()
	_display_name = display_name.strip_edges().left(24)
	_build_id = build_id.strip_edges()
	if _player_id.is_empty() or _build_id.is_empty():
		return {"ok": false, "error": "Oyuncu veya build kimliği eksik"}
	_manual_disconnect = false
	_disconnect_flush_in_progress = false
	_reconnect_in_progress = false
	_reconnect_attempt = 0
	_authenticated = false
	_local_team_id = -1
	_command_sequence = 0
	_last_ack_sequence = -1
	_pending_pings.clear()
	_ping_samples.clear()
	_sent_ping_count = 0
	_lost_ping_count = 0
	NetworkSession.set_connection_state(
		NetworkSession.ConnectionState.CONNECTING, "Oyun sunucusuna bağlanılıyor"
	)
	return _open_client_peer()


func has_persisted_reconnect_session(expected_build_id: String) -> bool:
	if _is_server or _reconnect_store == null:
		return false
	return _reconnect_store.has_session(expected_build_id, NetworkProtocol.VERSION)


func get_persisted_reconnect_summary(expected_build_id: String) -> Dictionary:
	if _is_server or _reconnect_store == null:
		return {}
	var session: Dictionary = _reconnect_store.load_session(
		expected_build_id, NetworkProtocol.VERSION
	)
	if session.is_empty():
		return {}
	var assignment: Dictionary = session.get("assignment", {}) as Dictionary
	return {
		"match_id": String(assignment.get("match_id", "")),
		"server_id": String(assignment.get("server_id", "")),
		"region_name": String(assignment.get("region_name", "")),
		"region_short_name": String(assignment.get("region_short_name", "")),
		"display_name": String(session.get("display_name", "")),
		"team_id": int(session.get("team_id", -1)),
		"resume_until_unix_msec": int(session.get("resume_until_unix_msec", 0)),
	}


func resume_persisted_session(expected_build_id: String) -> Dictionary:
	if _is_server or _reconnect_store == null:
		return {"ok": false, "error": "Yeniden bağlanma istemcide kullanılabilir"}
	var session: Dictionary = _reconnect_store.load_session(
		expected_build_id, NetworkProtocol.VERSION
	)
	if session.is_empty():
		return {"ok": false, "error": "Devam eden maç oturumu bulunamadı"}
	var assignment_variant: Variant = session.get("assignment", {})
	if not assignment_variant is Dictionary:
		_reconnect_store.clear()
		return {"ok": false, "error": "Kaydedilmiş sunucu ataması geçersiz"}
	var validation: Dictionary = NetworkProtocol.validate_reconnect_assignment(
		assignment_variant as Dictionary
	)
	if not bool(validation.get("ok", false)):
		_reconnect_store.clear()
		return validation
	_assignment = (validation.get("assignment", {}) as Dictionary).duplicate(true)
	_player_id = String(session.get("player_id", "")).strip_edges()
	_display_name = String(session.get("display_name", "")).strip_edges().left(24)
	_build_id = String(session.get("build_id", "")).strip_edges()
	_reconnect_token = String(session.get("reconnect_token", "")).strip_edges()
	_local_team_id = int(session.get("team_id", -1))
	if (
		_player_id.is_empty()
		or _build_id != expected_build_id
		or _reconnect_token.length() < 24
		or _local_team_id < 0
	):
		_reconnect_store.clear()
		return {"ok": false, "error": "Kaydedilmiş yeniden bağlanma verisi geçersiz"}
	_manual_disconnect = false
	_disconnect_flush_in_progress = false
	_reconnect_in_progress = false
	_reconnect_attempt = 0
	_authenticated = false
	_command_sequence = 0
	_last_ack_sequence = -1
	_pending_pings.clear()
	_ping_samples.clear()
	_sent_ping_count = 0
	_lost_ping_count = 0
	NetworkSession.set_online()
	NetworkSession.set_match_assignment(_assignment)
	NetworkSession.set_connection_state(
		NetworkSession.ConnectionState.CONNECTING, "Devam eden maça bağlanılıyor"
	)
	var open_result: Dictionary = _open_client_peer()
	if not bool(open_result.get("ok", false)):
		return open_result
	return {"ok": true, "assignment": _assignment.duplicate(true)}


func clear_persisted_reconnect_session() -> void:
	if _reconnect_store != null:
		_reconnect_store.clear()


func wait_for_authentication(timeout_seconds: float = 12.0) -> Dictionary:
	if _authenticated:
		return {"ok": true, "team_id": _local_team_id}
	var timeout: float = maxf(timeout_seconds, 1.0)
	var start_msec: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_msec < roundi(timeout * 1000.0):
		if _authenticated:
			return {"ok": true, "team_id": _local_team_id}
		if NetworkSession.connection_state == NetworkSession.ConnectionState.FAILED:
			return {"ok": false, "error": NetworkSession.connection_message}
		await get_tree().create_timer(0.05, true, false, true).timeout
	return {"ok": false, "error": "Oyun sunucusu kimlik doğrulaması zaman aşımına uğradı"}


func disconnect_from_game(reason: String = "İstemci ayrıldı") -> void:
	if _disconnect_flush_in_progress:
		return
	_manual_disconnect = true
	_reconnect_in_progress = false
	if (
		_authenticated
		and multiplayer.multiplayer_peer != null
		and (
			multiplayer.multiplayer_peer.get_connection_status()
			== MultiplayerPeer.CONNECTION_CONNECTED
		)
	):
		_disconnect_flush_in_progress = true
		_rpc_client_leave.rpc_id(NetworkProtocol.SERVER_PEER_ID)
		_finish_manual_disconnect.call_deferred(reason)
		return
	_finish_manual_disconnect_immediate(reason)


func _finish_manual_disconnect(reason: String) -> void:
	await get_tree().create_timer(0.12, true, false, true).timeout
	_finish_manual_disconnect_immediate(reason)


func _finish_manual_disconnect_immediate(reason: String) -> void:
	_disconnect_flush_in_progress = false
	_authenticated = false
	clear_persisted_reconnect_session()
	_close_peer()
	_pending_pings.clear()
	NetworkSession.set_connection_state(NetworkSession.ConnectionState.IDLE, reason)


func send_command(command_type: StringName, payload: Dictionary = {}) -> bool:
	if _is_server or not _authenticated or multiplayer.multiplayer_peer == null:
		return false
	_command_sequence += 1
	var command: Dictionary = NetworkProtocol.make_command(
		_command_sequence, _last_server_tick, command_type, payload
	)
	if command_type == &"move":
		_rpc_submit_command_unreliable.rpc_id(NetworkProtocol.SERVER_PEER_ID, command)
	else:
		_rpc_submit_command_reliable.rpc_id(NetworkProtocol.SERVER_PEER_ID, command)
	return true


func get_local_team_id() -> int:
	return _local_team_id


func get_last_server_tick() -> int:
	return _last_server_tick


func is_authenticated() -> bool:
	return _authenticated


func get_reconnect_token() -> String:
	return _reconnect_token


func is_server_ready() -> bool:
	if not _is_server or _peer == null or not is_instance_valid(_match):
		return false
	if bool(_match.get("match_finished")):
		return false
	if OS.is_debug_build():
		return true
	return (
		not _server_match_id.is_empty()
		and not _server_id.is_empty()
		and not _server_build_id.is_empty()
	)


func get_transport_stats() -> Dictionary:
	return {
		"authenticated": _authenticated,
		"connected_players": _peer_records.size(),
		"expected_players":
		_match_start_gate.get_expected_players() if _match_start_gate != null else 1,
		"human_player_count": _human_player_count,
		"bot_count": _bot_count,
		"ranked_match": _ranked_match,
		"match_started": _match_start_gate.is_started() if _match_start_gate != null else false,
		"server_tick": _last_server_tick,
		"command_sequence": _command_sequence,
		"ack_sequence": _last_ack_sequence,
		"pending_pings": _pending_pings.size(),
		"reconnect_attempt": _reconnect_attempt,
		"persisted_reconnect":
		has_persisted_reconnect_session(_build_id) if not _build_id.is_empty() else false,
		"match_id": _server_match_id if _is_server else String(_assignment.get("match_id", "")),
		"server_id": _server_id if _is_server else String(_assignment.get("server_id", "")),
		"build_id": _server_build_id if _is_server else _build_id,
		"auth_pending": _auth_in_progress.size(),
		"reconnect_reservations": _reservations_by_player.size(),
		"auth_accepted_total": _metric_auth_accepted_total,
		"auth_rejected_total": _metric_auth_rejected_total,
		"reconnect_success_total": _metric_reconnect_success_total,
		"commands_received_total": _metric_commands_received_total,
		"snapshots_sent_total": _metric_snapshots_sent_total,
		"match_result_failures_total": _metric_match_result_failures_total,
	}


func _open_client_peer() -> Dictionary:
	_close_peer()
	var host: String = String(_assignment.get("host", ""))
	var port: int = int(_assignment.get("port", 0))
	_peer = ENetMultiplayerPeer.new()
	var error: Error = _peer.create_client(host, port, NetworkProtocol.ENET_CHANNEL_COUNT, 0, 0, 0)
	if error != OK:
		_peer = null
		var message: String = "ENet bağlantısı oluşturulamadı: %s" % error_string(error)
		NetworkSession.set_connection_state(NetworkSession.ConnectionState.FAILED, message)
		client_connection_failed.emit(message)
		return {"ok": false, "error": message}
	multiplayer.multiplayer_peer = _peer
	return {"ok": true}


func _close_peer() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(peer_id: int) -> void:
	if not _is_server:
		return
	_auth_deadlines[peer_id] = (
		Time.get_ticks_msec() + roundi(NetworkProtocol.AUTH_TIMEOUT_SECONDS * 1000.0)
	)


func _on_peer_disconnected(peer_id: int) -> void:
	_auth_deadlines.erase(peer_id)
	_auth_in_progress.erase(peer_id)
	if not _is_server:
		return
	var record_variant: Variant = _peer_records.get(peer_id, null)
	if not record_variant is Dictionary:
		return
	var record: Dictionary = record_variant
	_peer_records.erase(peer_id)
	var player_id: String = String(record.get("player_id", ""))
	var team_id: int = int(record.get("team_id", -1))
	if is_instance_valid(_match) and team_id >= 0:
		_match.detach_peer_for_reconnect(peer_id)
	var expires_msec: int = (
		Time.get_ticks_msec() + roundi(NetworkProtocol.RECONNECT_GRACE_SECONDS * 1000.0)
	)
	_reservations_by_player[player_id] = {
		"team_id": team_id,
		"display_name": String(record.get("display_name", "")),
		"reconnect_token": String(record.get("reconnect_token", "")),
		"expires_msec": expires_msec,
	}
	_mark_participant_disconnected(player_id, true)
	server_peer_released.emit(peer_id, team_id)


func _on_connected_to_server() -> void:
	client_connected.emit()
	NetworkSession.set_connection_state(
		NetworkSession.ConnectionState.AUTHENTICATING, "Sunucu bileti doğrulanıyor"
	)
	_rpc_client_hello.rpc_id(
		NetworkProtocol.SERVER_PEER_ID,
		String(_assignment.get("join_ticket", "")),
		_player_id,
		_display_name,
		_build_id,
		NetworkProtocol.VERSION,
		String(_assignment.get("match_id", "")),
		String(_assignment.get("server_id", "")),
		_reconnect_token
	)


func _on_connection_failed() -> void:
	var message: String = "Oyun sunucusuna bağlantı kurulamadı"
	if _reconnect_in_progress:
		return
	NetworkSession.set_connection_state(NetworkSession.ConnectionState.FAILED, message)
	client_connection_failed.emit(message)


func _on_server_disconnected() -> void:
	_authenticated = false
	if _manual_disconnect:
		client_disconnected.emit("Bağlantı kapatıldı")
		return
	if _reconnect_token.is_empty() or _assignment.is_empty():
		var message: String = "Oyun sunucusu bağlantısı kesildi"
		NetworkSession.set_connection_state(NetworkSession.ConnectionState.FAILED, message)
		client_disconnected.emit(message)
		return
	_begin_reconnect()


func _begin_reconnect() -> void:
	if _reconnect_in_progress:
		return
	_reconnect_in_progress = true
	_reconnect_attempt = 0
	_reconnect_deadline_msec = (
		Time.get_ticks_msec() + roundi(NetworkProtocol.RECONNECT_GRACE_SECONDS * 1000.0)
	)
	NetworkSession.set_connection_state(
		NetworkSession.ConnectionState.RECONNECTING, "Bağlantı yeniden kuruluyor"
	)


func _client_process(delta: float) -> void:
	if _reconnect_in_progress:
		_process_reconnect(delta)
	if not _authenticated:
		return
	_ping_left -= delta
	if _ping_left <= 0.0:
		_ping_left = NetworkProtocol.PING_INTERVAL_SECONDS
		_send_ping()
	_prune_timed_out_pings()
	var now_msec: int = Time.get_ticks_msec()
	if (
		now_msec - _last_reconnect_persist_msec
		>= roundi(NetworkProtocol.RECONNECT_PERSIST_REFRESH_SECONDS * 1000.0)
	):
		_persist_reconnect_session()


func _process_reconnect(_delta: float) -> void:
	if Time.get_ticks_msec() >= _reconnect_deadline_msec:
		_reconnect_in_progress = false
		var message: String = "Yeniden bağlanma süresi doldu"
		NetworkSession.set_connection_state(NetworkSession.ConnectionState.FAILED, message)
		clear_persisted_reconnect_session()
		reconnect_failed.emit(message)
		return
	if _peer != null and _peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	var now_msec: int = Time.get_ticks_msec()
	var next_attempt_msec: int = int(get_meta("next_reconnect_msec", 0))
	if now_msec < next_attempt_msec:
		return
	_reconnect_attempt += 1
	reconnect_started.emit(_reconnect_attempt)
	set_meta(
		"next_reconnect_msec", now_msec + roundi(NetworkProtocol.RECONNECT_RETRY_SECONDS * 1000.0)
	)
	_open_client_peer()


func _server_process(delta: float) -> void:
	var now_msec: int = Time.get_ticks_msec()
	var gate_result: Dictionary = (
		_match_start_gate.advance(_peer_records.size(), now_msec)
		if _match_start_gate != null
		else {}
	)
	if bool(gate_result.get("started", false)):
		_on_server_match_started()
	if bool(gate_result.get("shutdown", false)):
		push_warning("Dedicated server closed because no authenticated player joined")
		get_tree().quit(0)
	if _match_start_gate == null or _match_start_gate.is_started():
		_snapshot_left -= delta
		if _snapshot_left <= 0.0:
			_snapshot_left = 1.0 / NetworkProtocol.SNAPSHOT_HZ
			_broadcast_snapshots()
	for peer_id_variant in _auth_deadlines.keys():
		var peer_id: int = int(peer_id_variant)
		if now_msec >= int(_auth_deadlines[peer_id]):
			_auth_deadlines.erase(peer_id)
			_disconnect_peer(peer_id)
	for player_id_variant in _reservations_by_player.keys():
		var player_id: String = String(player_id_variant)
		var reservation: Dictionary = _reservations_by_player[player_id]
		if now_msec < int(reservation.get("expires_msec", 0)):
			continue
		_reservations_by_player.erase(player_id)
		if is_instance_valid(_match):
			_match.release_reserved_team_to_ai(int(reservation.get("team_id", -1)))


func _consider_server_match_start() -> void:
	if (
		_match_start_gate != null
		and _match_start_gate.consider_start(_peer_records.size(), Time.get_ticks_msec())
	):
		_on_server_match_started()


func _on_server_match_started() -> void:
	_server_started_unix_msec = roundi(Time.get_unix_time_from_system() * 1000.0)
	var connected_players := _peer_records.size()
	var expected_players := (
		_match_start_gate.get_expected_players() if _match_start_gate != null else 1
	)
	if connected_players < expected_players:
		_human_player_count = connected_players
		_bot_count = maxi(_max_players - connected_players, 0)
		_ranked_match = false
	print(
		(
			"[GameTransport] Authoritative match started with %d/%d authenticated players"
			% [connected_players, expected_players]
		)
	)


func _broadcast_snapshots() -> void:
	if not is_instance_valid(_match):
		return
	for peer_id_variant in _peer_records.keys():
		var peer_id: int = int(peer_id_variant)
		var record: Dictionary = _peer_records[peer_id]
		var team_id: int = int(record.get("team_id", -1))
		if team_id < 0:
			continue
		var snapshot: Dictionary = _match.build_network_snapshot_for_team(team_id)
		snapshot["ack_sequence"] = _match.get_last_command_sequence(peer_id)
		snapshot["server_time_msec"] = Time.get_ticks_msec()
		_rpc_receive_snapshot.rpc_id(peer_id, snapshot)
		_metric_snapshots_sent_total += 1


func _mark_participant_disconnected(player_id: String, disconnected: bool) -> void:
	if player_id.is_empty() or not _participant_history.has(player_id):
		return
	var entry: Dictionary = _participant_history[player_id]
	entry["disconnected"] = disconnected
	_participant_history[player_id] = entry


func _report_match_result_and_shutdown(winner_name: String) -> void:
	var payload: Dictionary = _build_match_result_payload(winner_name)
	var reported: bool = false
	var control_url: String = OS.get_environment("CONTROL_BASE_URL").trim_suffix("/")
	var server_token: String = OS.get_environment("GAME_SERVER_AUTH_TOKEN")
	if not control_url.is_empty() and not server_token.is_empty():
		for attempt in MATCH_RESULT_RETRY_COUNT:
			var result_client := HTTP_CLIENT_SCRIPT.new() as HttpJsonClient
			result_client.name = "MatchResultHTTP_%d" % attempt
			result_client.timeout_seconds = 6.0
			add_child(result_client)
			var response: Dictionary = await (
				result_client
				. request_json(
					HTTPClient.METHOD_POST,
					"%s/v1/internal/matches/result" % control_url,
					PackedStringArray(
						[
							"Authorization: Bearer %s" % server_token,
							"Accept: application/json",
						]
					),
					payload
				)
			)
			result_client.queue_free()
			if bool(response.get("ok", false)):
				reported = true
				break
			await get_tree().create_timer(1.0, true, false, true).timeout
	if not reported:
		_metric_match_result_failures_total += 1
		push_warning("Authoritative match result could not be persisted")
	await get_tree().create_timer(SERVER_SHUTDOWN_DELAY_SECONDS, true, false, true).timeout
	get_tree().quit(0)


func _build_match_result_payload(winner_name: String) -> Dictionary:
	var participant_rows: Array[Dictionary] = []
	var winner_team: int = -1
	if is_instance_valid(_match):
		for controller_variant in _match.controllers:
			var controller := controller_variant as ColonyController
			if is_instance_valid(controller) and controller.display_name == winner_name:
				winner_team = controller.team_id
	var sortable: Array[Dictionary] = []
	for player_id_variant in _participant_history.keys():
		var player_id: String = String(player_id_variant)
		var history: Dictionary = _participant_history[player_id]
		var team_id: int = int(history.get("team_id", -1))
		var score: int = 0
		if is_instance_valid(_match) and team_id >= 0 and team_id < _match.controllers.size():
			var controller: ColonyController = _match.controllers[team_id]
			if is_instance_valid(controller):
				score = maxi(controller.get_score(), 0)
		(
			sortable
			. append(
				{
					"player_id": player_id,
					"team_id": team_id,
					"score": score,
					"disconnected": bool(history.get("disconnected", false)),
					"winner": team_id == winner_team,
				}
			)
		)
	sortable.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if bool(a.get("winner", false)) != bool(b.get("winner", false)):
				return bool(a.get("winner", false))
			return int(a.get("score", 0)) > int(b.get("score", 0))
	)
	for index in sortable.size():
		var row: Dictionary = sortable[index]
		row.erase("winner")
		row["placement"] = index + 1
		participant_rows.append(row)
	return {
		"match_id": _server_match_id,
		"server_id": _server_id,
		"region_id": OS.get_environment("REGION_ID").strip_edges(),
		"build_id": _server_build_id,
		"protocol_version": NetworkProtocol.VERSION,
		"started_at_ms": _server_started_unix_msec,
		"ended_at_ms": roundi(Time.get_unix_time_from_system() * 1000.0),
		"termination_reason": "completed",
		"ranked": _ranked_match,
		"participants": participant_rows,
	}


func _send_ping() -> void:
	_ping_nonce += 1
	var now_msec: int = Time.get_ticks_msec()
	_pending_pings[_ping_nonce] = now_msec
	_sent_ping_count += 1
	_rpc_ping.rpc_id(NetworkProtocol.SERVER_PEER_ID, _ping_nonce, now_msec)


func _prune_timed_out_pings() -> void:
	var now_msec: int = Time.get_ticks_msec()
	for nonce_variant in _pending_pings.keys():
		var nonce: int = int(nonce_variant)
		if (
			now_msec - int(_pending_pings[nonce])
			< roundi(NetworkProtocol.PING_TIMEOUT_SECONDS * 1000.0)
		):
			continue
		_pending_pings.erase(nonce)
		_lost_ping_count += 1
	_update_network_metrics()


func _update_network_metrics() -> void:
	var ping_value: int = -1
	var jitter_value: int = -1
	if not _ping_samples.is_empty():
		var sorted_samples: Array[float] = _ping_samples.duplicate()
		sorted_samples.sort()
		var median: float = _median_sample(sorted_samples)
		ping_value = roundi(median)
		if _ping_samples.size() > 1:
			var deviations: Array[float] = []
			for sample in _ping_samples:
				deviations.append(absf(sample - median))
			deviations.sort()
			jitter_value = roundi(_median_sample(deviations))
	var total: int = maxi(_sent_ping_count, 1)
	var loss: float = clampf(float(_lost_ping_count) / float(total), 0.0, 1.0)
	NetworkSession.apply_live_metrics(ping_value, jitter_value, loss)


func _median_sample(sorted_samples: Array[float]) -> float:
	if sorted_samples.is_empty():
		return 0.0
	var middle: int = sorted_samples.size() / 2
	if sorted_samples.size() % 2 == 1:
		return sorted_samples[middle]
	return (sorted_samples[middle - 1] + sorted_samples[middle]) * 0.5


func _on_server_match_ended(winner_name: String, _player_won: bool) -> void:
	if not _is_server:
		return
	for peer_id_variant in _peer_records.keys():
		_rpc_match_ended.rpc_id(int(peer_id_variant), winner_name)
	if not _match_result_reporting:
		_match_result_reporting = true
		_report_match_result_and_shutdown.call_deferred(winner_name)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_client_hello(
	join_ticket: String,
	player_id: String,
	display_name: String,
	build_id: String,
	protocol_version: int,
	match_id: String,
	server_id: String,
	reconnect_token: String
) -> void:
	if not _is_server:
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if _peer_records.has(peer_id) or _auth_in_progress.has(peer_id):
		return
	_auth_in_progress[peer_id] = true
	call_deferred(
		"_authenticate_peer",
		peer_id,
		join_ticket,
		player_id,
		display_name,
		build_id,
		protocol_version,
		match_id,
		server_id,
		reconnect_token
	)


func _authenticate_peer(
	peer_id: int,
	join_ticket: String,
	player_id: String,
	display_name: String,
	build_id: String,
	protocol_version: int,
	match_id: String,
	server_id: String,
	reconnect_token: String
) -> void:
	if _peer_records.has(peer_id):
		_auth_in_progress.erase(peer_id)
		return
	if protocol_version != NetworkProtocol.VERSION:
		_reject_peer(peer_id, "Ağ protokolü uyumsuz")
		return
	if not _validate_server_identity_claims(match_id, server_id, build_id):
		_reject_peer(peer_id, "Sunucu veya build kimliği eşleşmiyor")
		return
	if not is_instance_valid(_match):
		_reject_peer(peer_id, "Maç henüz hazır değil")
		return
	var reconnect_result: Dictionary = _try_reconnect(
		player_id, reconnect_token, peer_id, display_name
	)
	if bool(reconnect_result.get("ok", false)):
		_auth_in_progress.erase(peer_id)
		return
	var validation: Dictionary = await _validate_join_ticket(
		join_ticket, player_id, protocol_version
	)
	if not bool(validation.get("ok", false)):
		_reject_peer(peer_id, String(validation.get("error", "Bilet doğrulanamadı")))
		return
	if not _is_peer_connected(peer_id):
		_auth_in_progress.erase(peer_id)
		return
	var trusted_display_name: String = (
		String(validation.get("display_name", display_name)).strip_edges().left(24)
	)
	if trusted_display_name.is_empty():
		trusted_display_name = "Player"
	var team_id: int = _match.assign_peer_to_available_team(peer_id, trusted_display_name)
	if team_id < 0:
		_reject_peer(peer_id, "Boş takım slotu bulunamadı")
		return
	var generated_token: String = _make_reconnect_token()
	_peer_records[peer_id] = {
		"player_id": player_id,
		"display_name": trusted_display_name,
		"team_id": team_id,
		"reconnect_token": generated_token,
	}
	_participant_history[player_id] = {
		"player_id": player_id,
		"display_name": trusted_display_name,
		"team_id": team_id,
		"disconnected": false,
	}
	_auth_deadlines.erase(peer_id)
	_auth_in_progress.erase(peer_id)
	_rpc_server_accept.rpc_id(
		peer_id, team_id, generated_token, _match.get_server_tick(), GameSession.get_match_seed()
	)
	_metric_auth_accepted_total += 1
	server_peer_authenticated.emit(peer_id, team_id, player_id)
	_consider_server_match_start()


func _try_reconnect(
	player_id: String, token: String, peer_id: int, display_name: String
) -> Dictionary:
	if player_id.is_empty() or token.is_empty() or not _reservations_by_player.has(player_id):
		return {"ok": false}
	var reservation: Dictionary = _reservations_by_player[player_id]
	if (
		Time.get_ticks_msec() >= int(reservation.get("expires_msec", 0))
		or token != String(reservation.get("reconnect_token", ""))
	):
		return {"ok": false}
	var team_id: int = int(reservation.get("team_id", -1))
	var trusted_display_name: String = (
		String(reservation.get("display_name", display_name)).strip_edges().left(24)
	)
	if trusted_display_name.is_empty():
		trusted_display_name = "Player"
	if (
		not is_instance_valid(_match)
		or not _match.assign_peer_to_team(peer_id, team_id, trusted_display_name)
	):
		return {"ok": false}
	_reservations_by_player.erase(player_id)
	_peer_records[peer_id] = {
		"player_id": player_id,
		"display_name": trusted_display_name,
		"team_id": team_id,
		"reconnect_token": token,
	}
	_participant_history[player_id] = {
		"player_id": player_id,
		"display_name": trusted_display_name,
		"team_id": team_id,
		"disconnected": false,
	}
	_auth_deadlines.erase(peer_id)
	_rpc_server_accept.rpc_id(
		peer_id, team_id, token, _match.get_server_tick(), GameSession.get_match_seed()
	)
	_metric_auth_accepted_total += 1
	_metric_reconnect_success_total += 1
	server_peer_authenticated.emit(peer_id, team_id, player_id)
	_consider_server_match_start()
	return {"ok": true}


func _validate_join_ticket(
	join_ticket: String, player_id: String, protocol_version: int
) -> Dictionary:
	if join_ticket.is_empty() or player_id.is_empty():
		return {"ok": false, "error": "Eksik bağlantı bileti"}
	var expected_ticket: String = OS.get_environment("EXPECTED_JOIN_TICKET")
	var expected_player_id: String = OS.get_environment("EXPECTED_PLAYER_ID")
	if not expected_ticket.is_empty() or not expected_player_id.is_empty():
		if expected_ticket.is_empty() or expected_player_id.is_empty():
			return {"ok": false, "error": "Sunucu bilet kimliği eksik yapılandırıldı"}
		if not _constant_time_equal(join_ticket, expected_ticket):
			return {"ok": false, "error": "Bağlantı bileti eşleşmiyor"}
		if not _constant_time_equal(player_id, expected_player_id):
			return {"ok": false, "error": "Oyuncu kimliği biletle eşleşmiyor"}
		var ticket_hash: String = join_ticket.sha256_text()
		if _consumed_join_ticket_hashes.has(ticket_hash):
			return {"ok": false, "error": "Bağlantı bileti daha önce kullanıldı"}
		_consumed_join_ticket_hashes[ticket_hash] = true
		return {
			"ok": true,
			"display_name": OS.get_environment("EXPECTED_DISPLAY_NAME").strip_edges().left(24),
		}
	var control_url: String = OS.get_environment("CONTROL_BASE_URL").trim_suffix("/")
	var server_token: String = OS.get_environment("GAME_SERVER_AUTH_TOKEN")
	if not control_url.is_empty() and not server_token.is_empty():
		var ticket_client := HTTP_CLIENT_SCRIPT.new() as HttpJsonClient
		ticket_client.name = "JoinTicketHTTP_%d" % Time.get_ticks_msec()
		ticket_client.timeout_seconds = 5.0
		add_child(ticket_client)
		var response: Dictionary = await (
			ticket_client
			. request_json(
				HTTPClient.METHOD_POST,
				"%s/v1/internal/sessions/consume" % control_url,
				PackedStringArray(
					[
						"Authorization: Bearer %s" % server_token,
						"Accept: application/json",
					]
				),
				{
					"join_ticket": join_ticket,
					"player_id": player_id,
					"match_id": _server_match_id,
					"server_id": _server_id,
					"build_id": _server_build_id,
					"protocol_version": protocol_version,
				}
			)
		)
		ticket_client.queue_free()
		if not bool(response.get("ok", false)):
			return {
				"ok": false, "error": String(response.get("error", "Bilet servisine ulaşılamadı"))
			}
		var body_variant: Variant = response.get("body", {})
		if not body_variant is Dictionary:
			return {"ok": false, "error": "Bilet servisi geçersiz yanıt verdi"}
		var body: Dictionary = body_variant
		return {
			"ok": bool(body.get("ok", false)),
			"error": String(body.get("error", "Bilet reddedildi")),
			"display_name": String(body.get("displayName", "")),
		}
	if OS.is_debug_build():
		return {"ok": true, "dev": true}
	return {"ok": false, "error": "Sunucu bilet doğrulayıcısı yapılandırılmadı"}


func _constant_time_equal(left: String, right: String) -> bool:
	var left_bytes: PackedByteArray = left.to_utf8_buffer()
	var right_bytes: PackedByteArray = right.to_utf8_buffer()
	var maximum_size: int = maxi(left_bytes.size(), right_bytes.size())
	var difference: int = left_bytes.size() ^ right_bytes.size()
	for index in maximum_size:
		var left_byte: int = left_bytes[index] if index < left_bytes.size() else 0
		var right_byte: int = right_bytes[index] if index < right_bytes.size() else 0
		difference |= left_byte ^ right_byte
	return difference == 0


func _validate_server_identity_claims(
	match_id: String, server_id: String, build_id: String
) -> bool:
	if OS.is_debug_build():
		if _server_match_id.is_empty():
			_server_match_id = match_id.strip_edges()
		if _server_id.is_empty():
			_server_id = server_id.strip_edges()
	return (
		not _server_match_id.is_empty()
		and not _server_id.is_empty()
		and match_id == _server_match_id
		and server_id == _server_id
		and build_id == _server_build_id
	)


func _make_reconnect_token() -> String:
	var crypto := Crypto.new()
	return Marshalls.raw_to_base64(crypto.generate_random_bytes(32))


func _reject_peer(peer_id: int, message: String) -> void:
	_metric_auth_rejected_total += 1
	_auth_in_progress.erase(peer_id)
	_auth_deadlines.erase(peer_id)
	_rpc_server_reject.rpc_id(peer_id, message)
	await get_tree().create_timer(0.15, true, false, true).timeout
	_disconnect_peer(peer_id)


func _disconnect_peer(peer_id: int) -> void:
	if _peer != null:
		_peer.disconnect_peer(peer_id)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_server_accept(
	team_id: int, reconnect_token: String, server_tick: int, match_seed: int
) -> void:
	if _is_server:
		return
	_authenticated = true
	_reconnect_in_progress = false
	_local_team_id = team_id
	_reconnect_token = reconnect_token
	_last_server_tick = maxi(server_tick, 0)
	GameSession.local_team_id = team_id
	GameSession.set_match_seed(match_seed)
	NetworkSession.set_connection_state(NetworkSession.ConnectionState.CONNECTED, "Bağlandı")
	_persist_reconnect_session()
	client_authenticated.emit(team_id, reconnect_token)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_server_reject(message: String) -> void:
	if _is_server:
		return
	_authenticated = false
	clear_persisted_reconnect_session()
	NetworkSession.set_connection_state(NetworkSession.ConnectionState.FAILED, message)
	client_connection_failed.emit(message)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_client_leave() -> void:
	if not _is_server or not is_instance_valid(_match):
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	var record_variant: Variant = _peer_records.get(peer_id, null)
	if not record_variant is Dictionary:
		return
	var record: Dictionary = record_variant
	var team_id: int = int(record.get("team_id", -1))
	_peer_records.erase(peer_id)
	_auth_deadlines.erase(peer_id)
	_mark_participant_disconnected(String(record.get("player_id", "")), true)
	_match.release_peer(peer_id)
	server_peer_released.emit(peer_id, team_id)
	_disconnect_peer(peer_id)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _rpc_submit_command_unreliable(command: Dictionary) -> void:
	_server_receive_command(command)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_submit_command_reliable(command: Dictionary) -> void:
	_server_receive_command(command)


func _server_receive_command(command: Dictionary) -> void:
	if not _is_server or not is_instance_valid(_match):
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if not _peer_records.has(peer_id):
		return
	_metric_commands_received_total += 1
	_match.receive_authoritative_command(peer_id, command)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rpc_receive_snapshot(snapshot: Dictionary) -> void:
	if _is_server:
		return
	var server_tick: int = int(snapshot.get("server_tick", -1))
	if server_tick < _last_server_tick:
		return
	_last_server_tick = server_tick
	var ack_sequence: int = int(snapshot.get("ack_sequence", -1))
	if ack_sequence > _last_ack_sequence:
		_last_ack_sequence = ack_sequence
		command_acknowledged.emit(ack_sequence)
	var player_variant: Variant = snapshot.get("player", {})
	if player_variant is Dictionary:
		player_state_received.emit(player_variant as Dictionary)
	# Signals are synchronous and consumers treat the snapshot as read-only.
	# Avoid two deep copies of the full entity array every 50 ms on mobile.
	snapshot_received.emit(snapshot)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_match_ended(winner_name: String) -> void:
	if _is_server:
		return
	clear_persisted_reconnect_session()
	match_ended.emit(winner_name)


@rpc("any_peer", "call_remote", "unreliable", 3)
func _rpc_ping(nonce: int, client_send_msec: int) -> void:
	if not _is_server:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _peer_records.has(sender):
		return
	_rpc_pong.rpc_id(sender, nonce, client_send_msec, Time.get_ticks_msec())


@rpc("authority", "call_remote", "unreliable", 3)
func _rpc_pong(nonce: int, client_send_msec: int, _server_receive_msec: int) -> void:
	if _is_server or not _pending_pings.has(nonce):
		return
	_pending_pings.erase(nonce)
	var rtt: float = float(maxi(Time.get_ticks_msec() - client_send_msec, 0))
	_ping_samples.append(rtt)
	if _ping_samples.size() > 12:
		_ping_samples.pop_front()
	_update_network_metrics()


func _is_peer_connected(peer_id: int) -> bool:
	if peer_id <= 0 or multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.get_peers().has(peer_id)


func _get_bound_match() -> Node:
	return _match


func _persist_reconnect_session() -> void:
	if (
		_is_server
		or not _authenticated
		or _reconnect_store == null
		or _assignment.is_empty()
		or _reconnect_token.is_empty()
		or _player_id.is_empty()
		or _local_team_id < 0
	):
		return
	var now_unix_msec: int = roundi(Time.get_unix_time_from_system() * 1000.0)
	var saved: bool = (
		_reconnect_store
		. save_session(
			{
				"format_version": ReconnectSessionStore.FORMAT_VERSION,
				"assignment": _assignment,
				"player_id": _player_id,
				"display_name": _display_name,
				"build_id": _build_id,
				"protocol_version": NetworkProtocol.VERSION,
				"reconnect_token": _reconnect_token,
				"team_id": _local_team_id,
				"resume_until_unix_msec":
				now_unix_msec + roundi(NetworkProtocol.RECONNECT_PERSIST_TTL_SECONDS * 1000.0),
				"saved_at_unix_msec": now_unix_msec,
			}
		)
	)
	if saved:
		_last_reconnect_persist_msec = Time.get_ticks_msec()


func _detect_server_mode() -> bool:
	return DedicatedMatchStartGate.is_server_mode()
