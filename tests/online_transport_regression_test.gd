extends SceneTree

const REQUIRED_RESOURCES: Array[String] = [
	"res://network/network_protocol.gd",
	"res://network/game_transport.gd",
	"res://network/rivet_game_transport.gd",
	"res://network/dedicated_server_health.gd",
	"res://gameplay/network/network_entity_proxy.gd",
	"res://gameplay/network/online_match_client.gd",
	"res://ui/online_match_hud.gd",
	"res://scenes/online_game.tscn",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for path in REQUIRED_RESOURCES:
		if not ResourceLoader.exists(path):
			failures.append("Missing online resource: %s" % path)

	var future_assignment := {
		"match_id": "00000000-0000-0000-0000-000000000001",
		"server_id": "server-test",
		"transport": NetworkProtocol.TRANSPORT_WEBSOCKET,
		"websocket_url": "wss://api.rivet.dev/gateway/test@token/websocket/",
		"host": "api.rivet.dev",
		"port": 443,
		"join_ticket": "0123456789abcdef0123456789abcdef",
		"region_id": "eu",
		"region_name": "Avrupa",
		"region_short_name": "EU",
		"expires_at": int(Time.get_unix_time_from_system() * 1000.0) + 60_000,
		"protocol_version": NetworkProtocol.VERSION,
		"human_players": NetworkProtocol.DEFAULT_MAX_PLAYERS,
		"bot_players": 0,
		"ranked": true,
	}
	var validation: Dictionary = NetworkProtocol.validate_assignment(future_assignment)
	if not bool(validation.get("ok", false)):
		failures.append("Valid Rivet WebSocket assignment was rejected")
	future_assignment["websocket_url"] = "https://api.rivet.dev/not-websocket"
	if bool(NetworkProtocol.validate_assignment(future_assignment).get("ok", false)):
		failures.append("Non-WebSocket Rivet endpoint was accepted")
	future_assignment["websocket_url"] = "wss://api.rivet.dev/gateway/test@token/websocket/"
	future_assignment["protocol_version"] = NetworkProtocol.VERSION + 1
	if bool(NetworkProtocol.validate_assignment(future_assignment).get("ok", false)):
		failures.append("Protocol mismatch was accepted")
	future_assignment["protocol_version"] = NetworkProtocol.VERSION
	future_assignment["match_id"] = ""
	if bool(NetworkProtocol.validate_assignment(future_assignment).get("ok", false)):
		failures.append("Assignment without match identity was accepted")
	future_assignment["match_id"] = "00000000-0000-0000-0000-000000000001"
	future_assignment["server_id"] = ""
	if bool(NetworkProtocol.validate_assignment(future_assignment).get("ok", false)):
		failures.append("Assignment without server identity was accepted")
	future_assignment["server_id"] = "server-test"
	future_assignment["human_players"] = 3
	future_assignment["bot_players"] = 7
	future_assignment["ranked"] = true
	if bool(NetworkProtocol.validate_assignment(future_assignment).get("ok", false)):
		failures.append("Ranked assignment containing bots was accepted")
	future_assignment["ranked"] = false
	if not bool(NetworkProtocol.validate_assignment(future_assignment).get("ok", false)):
		failures.append("Valid unranked bot-backfilled assignment was rejected")
	future_assignment["human_players"] = 4
	if bool(NetworkProtocol.validate_assignment(future_assignment).get("ok", false)):
		failures.append("Assignment with more than ten total participants was accepted")
	future_assignment["human_players"] = NetworkProtocol.DEFAULT_MAX_PLAYERS
	future_assignment["bot_players"] = 0
	future_assignment["ranked"] = true
	if NetworkProtocol.ENET_CHANNEL_COUNT < 4:
		failures.append("Transport must expose four logical channels")
	if NetworkProtocol.MAX_SNAPSHOT_ENTITIES > 160:
		failures.append("Mobile snapshot budget is too large")
	if NetworkProtocol.DEFAULT_MAX_PLAYERS != 10:
		failures.append("Protocol player capacity differs from the ten-colony match")
	if NetworkProtocol.RECONNECT_GRACE_SECONDS < 60.0:
		failures.append("Reconnect reservation is shorter than 60 seconds")
	if NetworkProtocol.SERVER_JOIN_TIMEOUT_SECONDS < 60.0:
		failures.append("Dedicated empty-server timeout is too short")

	var proxy := NetworkEntityProxy.new()
	root.add_child(proxy)
	proxy.configure(11, 0, &"commander")
	proxy.apply_snapshot(
		{"team": 0, "kind": &"commander", "position": Vector2i(200, -400), "health": 255}, 1
	)
	if not proxy.authoritative_position.is_equal_approx(Vector2(100.0, -200.0)):
		failures.append("Quantized network position was decoded incorrectly")
	proxy.queue_free()

	if failures.is_empty():
		print("PASS online_transport_regression_test")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
