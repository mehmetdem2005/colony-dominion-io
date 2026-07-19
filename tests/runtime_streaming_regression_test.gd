extends SceneTree

const MATCH_SCENE := preload("res://scenes/server_game.tscn")
const CAMERA_SCRIPT := preload("res://gameplay/world/camera_controller.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var viewport_filter: int = int(
		ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", -1)
	)
	if viewport_filter != 2:
		_fail("Viewport default canvas filter is outside the Godot 4.6 valid runtime range")
		return

	var camera := CAMERA_SCRIPT.new() as PlayerCameraController
	if camera.process_callback != Camera2D.CAMERA2D_PROCESS_PHYSICS:
		camera.free()
		_fail("Camera2D is not explicitly configured for physics processing")
		return
	camera.free()

	var match := MATCH_SCENE.instantiate() as MatchController
	root.add_child(match)
	await process_frame
	if match.controllers.size() < 2:
		_fail("Server match did not create a bot colony")
		return

	var controller: ColonyController = match.controllers[1]
	controller.set_simulation_tier(ColonyController.SimulationTier.DORMANT)
	var before_positions: Dictionary = {}
	for unit in controller.units:
		if is_instance_valid(unit) and unit.is_alive():
			before_positions[unit.network_entity_id] = unit.global_position
			if unit.visible:
				_fail("Dormant unit remained visible")
				return

	var commander_before: Vector2 = controller.commander.global_position
	controller._bot_goal = commander_before + Vector2(600.0, 0.0)
	controller._bot_goal_left = 10.0
	controller._bot_decision_left = 10.0
	controller._run_dormant_navigation(ColonyController.DORMANT_NAVIGATION_INTERVAL)
	var commander_delta: Vector2 = controller.commander.global_position - commander_before
	if commander_delta.length_squared() <= 1.0:
		_fail("Dormant colony macro navigation did not advance")
		return
	for unit in controller.units:
		if not is_instance_valid(unit) or not unit.is_alive():
			continue
		var unit_before: Vector2 = before_positions.get(
			unit.network_entity_id, unit.global_position
		)
		var unit_delta: Vector2 = unit.global_position - unit_before
		if unit_delta.distance_to(commander_delta) > 0.01:
			_fail("Dormant group translation broke colony formation")
			return

	print(
		(
			"PASS runtime_streaming_regression_test dormant_delta=%s filter=%d"
			% [commander_delta, viewport_filter]
		)
	)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
