extends SceneTree

const REQUIRED_RESOURCES: Array[String] = [
	"res://network/network_protocol.gd",
	"res://network/game_transport.gd",
	"res://network/rivet_game_transport.gd",
	"res://network/edgegap_matchmaking_client.gd",
	"res://network/dedicated_server_health.gd",
	"res://gameplay/presentation/colony_visual_catalog.gd",
	"res://gameplay/network/network_entity_proxy.gd",
	"res://gameplay/network/online_match_client.gd",
	"res://ui/hud.gd",
	"res://scenes/ui/hud.tscn",
	"res://scenes/network/network_entity_proxy.tscn",
	"res://scenes/online_game.tscn",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for path in REQUIRED_RESOURCES:
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			failures.append("Missing online resource: %s" % path)

	var future_assignment := {
		"match_id": "00000000-0000-0000-0000-000000000001",
		"server_id": "edgegap-server-test",
		"transport": NetworkProtocol.TRANSPORT_ENET,
		"host": "203.0.113.10",
		"port": 32000,
		"join_ticket": "0123456789abcdef0123456789abcdef",
		"region_id": "frankfurt",
		"region_name": "Frankfurt",
		"region_short_name": "FRA",
		"expires_at": int(Time.get_unix_time_from_system() * 1000.0) + 60_000,
		"protocol_version": NetworkProtocol.VERSION,
		"human_players": 1,
		"bot_players": NetworkProtocol.DEFAULT_MAX_PLAYERS - 1,
		"ranked": false,
	}
	if not bool(NetworkProtocol.validate_assignment(future_assignment).get("ok", false)):
		failures.append("Valid Edgegap ENet assignment was rejected")
	future_assignment["port"] = 0
	if bool(NetworkProtocol.validate_assignment(future_assignment).get("ok", false)):
		failures.append("Edgegap assignment without a UDP port was accepted")
	future_assignment["port"] = 32000
	future_assignment["protocol_version"] = NetworkProtocol.VERSION + 1
	if bool(NetworkProtocol.validate_assignment(future_assignment).get("ok", false)):
		failures.append("Protocol mismatch was accepted")
	future_assignment["protocol_version"] = NetworkProtocol.VERSION
	future_assignment["match_id"] = ""
	if bool(NetworkProtocol.validate_assignment(future_assignment).get("ok", false)):
		failures.append("Assignment without match identity was accepted")
	future_assignment["match_id"] = "00000000-0000-0000-0000-000000000001"
	future_assignment["ranked"] = true
	if bool(NetworkProtocol.validate_assignment(future_assignment).get("ok", false)):
		failures.append("Ranked assignment containing bots was accepted")

	if NetworkProtocol.ENET_CHANNEL_COUNT < 4:
		failures.append("Transport must expose four logical channels")
	if NetworkProtocol.MAX_SNAPSHOT_ENTITIES > 160:
		failures.append("Mobile snapshot budget is too large")
	if NetworkProtocol.DEFAULT_MAX_PLAYERS != 10:
		failures.append("Protocol capacity differs from the ten-colony match")
	if NetworkProtocol.get_interpolation_delay_msec(1000) > 85:
		failures.append("Adaptive interpolation exceeds the mobile latency budget")

	var proxy_scene := load("res://scenes/network/network_entity_proxy.tscn") as PackedScene
	if proxy_scene == null:
		failures.append("Network proxy scene could not be loaded")
	else:
		var proxy := proxy_scene.instantiate() as NetworkEntityProxy
		root.add_child(proxy)
		proxy.configure(11, 0, &"commander")
		(
			proxy
			. apply_snapshot(
				{
					"team": 0,
					"kind": &"commander",
					"position": Vector2i(200, -400),
					"health": 255,
					"name": "Player",
				},
				1
			)
		)
		if not proxy.authoritative_position.is_equal_approx(Vector2(100.0, -200.0)):
			failures.append("Quantized network position was decoded incorrectly")
		var catalog: Node = root.get_node_or_null("UnitCatalog")
		var commander_definition: UnitDefinition = (
			catalog.call("get_definition", &"commander") as UnitDefinition
			if catalog != null
			else null
		)
		if commander_definition == null or proxy.sprite.texture != commander_definition.texture:
			failures.append("Online commander does not use the offline UnitCatalog asset")
		proxy.configure(12, 0, &"nest")
		if not proxy.visual_root.visible or proxy.sprite.texture == null:
			failures.append("Online nest asset is hidden")
		elif not proxy.sprite.texture.resource_path.ends_with("nest_blue.png"):
			failures.append("Online nest does not use the offline blue nest asset")
		proxy.queue_free()

	if failures.is_empty():
		print("PASS online_transport_regression_test")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
