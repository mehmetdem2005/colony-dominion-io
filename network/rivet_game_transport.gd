extends "res://network/game_transport.gd"

# Keeps the mature authentication, RPC, snapshot and reconnect implementation in
# game_transport.gd while replacing only the transport-specific peer lifecycle.

var _active_peer: MultiplayerPeer = null


func start_dedicated_server() -> Dictionary:
	if _active_peer != null:
		return {"ok": true, "port": _server_port}
	_is_server = true
	_server_port = DedicatedMatchStartGate.read_int_environment(
		"GAME_PORT", NetworkProtocol.DEFAULT_GAME_PORT, 1, 65535
	)
	_max_players = DedicatedMatchStartGate.read_int_environment(
		"MAX_PLAYERS", NetworkProtocol.DEFAULT_MAX_PLAYERS, 1, 10
	)
	var expected_players: int = DedicatedMatchStartGate.read_int_environment(
		"EXPECTED_PLAYERS", _max_players, 1, _max_players
	)
	if _match_start_gate != null:
		_match_start_gate.set_expected_players(expected_players)
	_server_match_id = OS.get_environment("MATCH_ID").strip_edges()
	_server_id = OS.get_environment("SERVER_ID").strip_edges()
	_server_build_id = OS.get_environment("BUILD_ID").strip_edges()
	_server_started_unix_msec = roundi(Time.get_unix_time_from_system() * 1000.0)
	if _server_build_id.is_empty():
		_server_build_id = "PHASE-05.4-RIVET-FULL-ONLINE"
	if not OS.is_debug_build() and (_server_match_id.is_empty() or _server_id.is_empty()):
		var identity_error := "Dedicated server MATCH_ID/SERVER_ID environment is missing"
		server_start_failed.emit(identity_error)
		push_error(identity_error)
		return {"ok": false, "error": identity_error}

	var transport: String = OS.get_environment("NETWORK_TRANSPORT").strip_edges().to_lower()
	if transport.is_empty():
		transport = NetworkProtocol.TRANSPORT_ENET
	var error: Error = OK
	if transport == NetworkProtocol.TRANSPORT_WEBSOCKET:
		var websocket_peer := WebSocketMultiplayerPeer.new()
		error = websocket_peer.create_server(_server_port, "127.0.0.1")
		if error == OK:
			_active_peer = websocket_peer
	elif transport == NetworkProtocol.TRANSPORT_ENET:
		var enet_peer := ENetMultiplayerPeer.new()
		enet_peer.set_bind_ip("*")
		var maximum_connections: int = mini(
			_max_players + NetworkProtocol.UNAUTHENTICATED_CONNECTION_HEADROOM, 64
		)
		error = enet_peer.create_server(
			_server_port, maximum_connections, NetworkProtocol.ENET_CHANNEL_COUNT
		)
		if error == OK:
			_active_peer = enet_peer
	else:
		error = ERR_INVALID_PARAMETER

	if error != OK or _active_peer == null:
		_active_peer = null
		var message: String = (
			"Ağ sunucusu başlatılamadı (%s): %s" % [transport, error_string(error)]
		)
		server_start_failed.emit(message)
		return {"ok": false, "error": message}

	multiplayer.multiplayer_peer = _active_peer
	server_started.emit(_server_port)
	print("[GameTransport] %s server listening on port %d" % [transport, _server_port])
	_health_server = HEALTH_SERVER_SCRIPT.new() as DedicatedServerHealth
	_health_server.name = "DedicatedServerHealth"
	add_child(_health_server)
	_health_server.configure(self, _get_bound_match)
	_health_server.start(
		DedicatedMatchStartGate.read_int_environment(
			"CONTROL_PORT", NetworkProtocol.DEFAULT_CONTROL_PORT, 1, 65535
		)
	)
	return {"ok": true, "port": _server_port, "transport": transport}


func is_server_ready() -> bool:
	if not _is_server or _active_peer == null or not is_instance_valid(_match):
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


func _open_client_peer() -> Dictionary:
	_close_peer()
	var transport: String = (
		String(_assignment.get("transport", NetworkProtocol.TRANSPORT_ENET))
		. strip_edges()
		. to_lower()
	)
	var error: Error = OK
	if transport == NetworkProtocol.TRANSPORT_WEBSOCKET:
		var websocket_url: String = String(_assignment.get("websocket_url", "")).strip_edges()
		var websocket_peer := WebSocketMultiplayerPeer.new()
		error = websocket_peer.create_client(websocket_url)
		if error == OK:
			_active_peer = websocket_peer
	elif transport == NetworkProtocol.TRANSPORT_ENET:
		var host: String = String(_assignment.get("host", ""))
		var port: int = int(_assignment.get("port", 0))
		var enet_peer := ENetMultiplayerPeer.new()
		error = enet_peer.create_client(host, port, NetworkProtocol.ENET_CHANNEL_COUNT, 0, 0, 0)
		if error == OK:
			_active_peer = enet_peer
	else:
		error = ERR_INVALID_PARAMETER

	if error != OK or _active_peer == null:
		_active_peer = null
		var message: String = (
			"Ağ bağlantısı oluşturulamadı (%s): %s" % [transport, error_string(error)]
		)
		NetworkSession.set_connection_state(NetworkSession.ConnectionState.FAILED, message)
		client_connection_failed.emit(message)
		return {"ok": false, "error": message}
	multiplayer.multiplayer_peer = _active_peer
	return {"ok": true, "transport": transport}


func _close_peer() -> void:
	if _active_peer != null:
		_active_peer.close()
	_active_peer = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _disconnect_peer(peer_id: int) -> void:
	if _active_peer != null:
		_active_peer.disconnect_peer(peer_id)


func _process_reconnect(_delta: float) -> void:
	if Time.get_ticks_msec() >= _reconnect_deadline_msec:
		_reconnect_in_progress = false
		var message: String = "Yeniden bağlanma süresi doldu"
		NetworkSession.set_connection_state(NetworkSession.ConnectionState.FAILED, message)
		clear_persisted_reconnect_session()
		reconnect_failed.emit(message)
		return
	if (
		_active_peer != null
		and _active_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED
	):
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
