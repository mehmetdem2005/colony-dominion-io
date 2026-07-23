extends SceneTree


func _initialize() -> void:
	var failures: Array[String] = []
	var online_scene := FileAccess.get_file_as_string("res://scenes/online_game.tscn")
	var offline_hud_scene := "res://scenes/ui/hud.tscn"
	if not online_scene.contains(offline_hud_scene):
		failures.append("Online match does not instance the shared offline HUD scene")
	if FileAccess.file_exists("res://ui/online_match_hud.gd"):
		failures.append("A duplicate online-only HUD implementation remains")

	var unit_source := FileAccess.get_file_as_string("res://gameplay/units/unit.gd")
	var colony_source := FileAccess.get_file_as_string("res://gameplay/colony/colony_controller.gd")
	var proxy_source := FileAccess.get_file_as_string(
		"res://gameplay/network/network_entity_proxy.gd"
	)
	for source_and_label in [
		[unit_source, "offline unit"],
		[colony_source, "offline colony"],
		[proxy_source, "online proxy"],
	]:
		if not String(source_and_label[0]).contains("ColonyVisualCatalog"):
			failures.append("%s bypasses the shared visual catalog" % source_and_label[1])

	var physics_start: int = proxy_source.find("func _physics_process")
	var next_function: int = proxy_source.find("\nfunc ", physics_start + 5)
	var physics_body: String = proxy_source.substr(
		physics_start, (next_function - physics_start) if next_function > physics_start else -1
	)
	if physics_body.contains("queue_redraw"):
		failures.append("Network proxy redraws every physics frame")

	var online_client := FileAccess.get_file_as_string(
		"res://gameplay/network/online_match_client.gd"
	)
	var anchor_guard: int = online_client.find("_camera_anchor == anchor")
	var world_prime: int = online_client.find("_world_stream.prime_initial_area()", anchor_guard)
	if anchor_guard < 0 or world_prime < anchor_guard:
		failures.append("World streaming is not guarded against per-snapshot re-priming")

	var transport := FileAccess.get_file_as_string("res://network/game_transport.gd")
	if transport.contains("snapshot_received.emit(snapshot.duplicate(true))"):
		failures.append("Snapshot receive path deep-copies the full swarm every tick")
	if not transport.contains("_median_sample"):
		failures.append("Live ping metric is not robust against startup spikes")
	if NetworkProtocol.get_interpolation_delay_msec(1000) > 85:
		failures.append("Interpolation adds more than 85 ms of artificial delay")

	var snapshot_builder := FileAccess.get_file_as_string(
		"res://gameplay/network/network_snapshot_builder.gd"
	)
	for marker in ["get_player_presentation_state", '"colonies"', '"name"', '"level"']:
		if not snapshot_builder.contains(marker):
			failures.append("Shared online presentation state is missing: %s" % marker)

	if failures.is_empty():
		print("PASS online_presentation_parity_regression_test")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
