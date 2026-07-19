class_name DedicatedServerHealth
extends Node

const MAX_CLIENTS: int = 16
const CLIENT_TIMEOUT_MSEC: int = 2000

var _server := TCPServer.new()
var _clients: Array[Dictionary] = []
var _transport: Node = null
var _match_provider: Callable
var _port: int = NetworkProtocol.DEFAULT_CONTROL_PORT
var _started: bool = false


func configure(transport: Node, match_provider: Callable) -> void:
	_transport = transport
	_match_provider = match_provider


func start(port: int) -> Error:
	_port = clampi(port, 1, 65535)
	var error: Error = _server.listen(_port, "*")
	_started = error == OK
	if _started:
		print("[ServerHealth] HTTP health listening on TCP %d" % _port)
	else:
		push_error("Server health port could not listen: %s" % error_string(error))
	return error


func _process(_delta: float) -> void:
	if not _started:
		return
	while _server.is_connection_available() and _clients.size() < MAX_CLIENTS:
		var peer: StreamPeerTCP = _server.take_connection()
		if peer != null:
			_clients.append({"peer": peer, "connected_msec": Time.get_ticks_msec()})
	for index in range(_clients.size() - 1, -1, -1):
		var record: Dictionary = _clients[index]
		var peer: StreamPeerTCP = record.get("peer") as StreamPeerTCP
		if peer == null:
			_clients.remove_at(index)
			continue
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_ERROR:
			_clients.remove_at(index)
			continue
		if peer.get_available_bytes() > 0:
			var request: String = peer.get_utf8_string(peer.get_available_bytes())
			_respond(peer, request)
			_clients.remove_at(index)
			continue
		if Time.get_ticks_msec() - int(record.get("connected_msec", 0)) > CLIENT_TIMEOUT_MSEC:
			peer.disconnect_from_host()
			_clients.remove_at(index)


func _exit_tree() -> void:
	for record in _clients:
		var peer: StreamPeerTCP = record.get("peer") as StreamPeerTCP
		if peer != null:
			peer.disconnect_from_host()
	_clients.clear()
	_server.stop()


func _respond(peer: StreamPeerTCP, request: String) -> void:
	var path: String = "/"
	var first_line: String = request.split("\r\n", false)[0] if not request.is_empty() else ""
	var parts: PackedStringArray = first_line.split(" ", false)
	if parts.size() >= 2:
		path = parts[1]
	var status_code: int = 200
	var content_type: String = "application/json"
	var response_body: String = ""
	var body: Dictionary = {}
	match path:
		"/health", "/v1/health":
			body = _build_health(false)
		"/ready", "/v1/ready":
			body = _build_health(true)
			if not bool(body.get("ready", false)):
				status_code = 503
		"/metrics", "/v1/metrics":
			body = _build_metrics()
		"/metrics/prometheus", "/v1/metrics/prometheus":
			body = _build_metrics()
			content_type = "text/plain; version=0.0.4"
			response_body = _build_prometheus(body)
		_:
			status_code = 404
			body = {"ok": false, "error": "not_found"}
	if response_body.is_empty():
		response_body = JSON.stringify(body)
	var status_text: String = (
		"OK"
		if status_code == 200
		else ("Service Unavailable" if status_code == 503 else "Not Found")
	)
	var response: String = (
		"HTTP/1.1 %d %s\r\n" % [status_code, status_text]
		+ "Content-Type: %s\r\n" % content_type
		+ "Content-Length: %d\r\n" % response_body.to_utf8_buffer().size()
		+ "Connection: close\r\n\r\n"
		+ response_body
	)
	peer.put_data(response.to_utf8_buffer())
	peer.disconnect_from_host()


func _build_health(require_ready: bool) -> Dictionary:
	var match_node: Node = _get_match()
	var ready: bool = is_instance_valid(match_node)
	if is_instance_valid(_transport) and _transport.has_method("is_server_ready"):
		ready = ready and bool(_transport.call("is_server_ready"))
	return {
		"ok": true if not require_ready else ready,
		"ready": ready,
		"build_id": OS.get_environment("BUILD_ID"),
		"protocol_version": NetworkProtocol.VERSION,
		"game_port":
		(
			int(OS.get_environment("GAME_PORT"))
			if OS.get_environment("GAME_PORT").is_valid_int()
			else NetworkProtocol.DEFAULT_GAME_PORT
		),
		"connected_players": _get_connected_players(),
		"now_msec": Time.get_ticks_msec(),
	}


func _build_metrics() -> Dictionary:
	var result: Dictionary = _build_health(false)
	if is_instance_valid(_transport) and _transport.has_method("get_transport_stats"):
		result["transport"] = _transport.call("get_transport_stats")
	var match_node: Node = _get_match()
	if is_instance_valid(match_node) and match_node.has_method("get_stream_stats"):
		result["match"] = match_node.call("get_stream_stats")
	return result


func _build_prometheus(metrics: Dictionary) -> String:
	var transport_variant: Variant = metrics.get("transport", {})
	var transport: Dictionary = transport_variant if transport_variant is Dictionary else {}
	var match_variant: Variant = metrics.get("match", {})
	var match_stats: Dictionary = match_variant if match_variant is Dictionary else {}
	var lines: PackedStringArray = PackedStringArray()
	_append_metric(lines, "colony_server_ready", 1 if bool(metrics.get("ready", false)) else 0)
	_append_metric(lines, "colony_connected_players", int(metrics.get("connected_players", 0)))
	_append_metric(lines, "colony_auth_pending", int(transport.get("auth_pending", 0)))
	_append_metric(
		lines, "colony_reconnect_reservations", int(transport.get("reconnect_reservations", 0))
	)
	_append_metric(
		lines, "colony_auth_accepted_total", int(transport.get("auth_accepted_total", 0))
	)
	_append_metric(
		lines, "colony_auth_rejected_total", int(transport.get("auth_rejected_total", 0))
	)
	_append_metric(
		lines, "colony_reconnect_success_total", int(transport.get("reconnect_success_total", 0))
	)
	_append_metric(
		lines, "colony_commands_received_total", int(transport.get("commands_received_total", 0))
	)
	_append_metric(
		lines, "colony_snapshots_sent_total", int(transport.get("snapshots_sent_total", 0))
	)
	_append_metric(
		lines,
		"colony_match_result_failures_total",
		int(transport.get("match_result_failures_total", 0))
	)
	_append_metric(
		lines,
		"colony_dropped_server_time_seconds",
		float(match_stats.get("dropped_server_time", 0.0))
	)
	_append_metric(
		lines,
		"colony_dropped_projectile_time_seconds",
		float(match_stats.get("dropped_projectile_time", 0.0))
	)
	_append_metric(lines, "colony_resident_chunks", int(match_stats.get("chunks", 0)))
	return "\n".join(lines) + "\n"


func _append_metric(lines: PackedStringArray, name: String, value: Variant) -> void:
	lines.append("# TYPE %s gauge" % name)
	lines.append("%s %s" % [name, str(value)])


func _get_match() -> Node:
	if not _match_provider.is_valid():
		return null
	return _match_provider.call() as Node


func _get_connected_players() -> int:
	if not is_instance_valid(_transport):
		return 0
	var stats_variant: Variant = _transport.call("get_transport_stats")
	if not stats_variant is Dictionary:
		return 0
	return int((stats_variant as Dictionary).get("connected_players", 0))
