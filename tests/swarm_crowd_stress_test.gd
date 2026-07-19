extends SceneTree

const MATCH_SCENE := preload("res://scenes/server_game.tscn")
const TARGET_MINIONS: int = 360
const SAMPLE_PHYSICS_FRAMES: int = 180


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var match := MATCH_SCENE.instantiate() as MatchController
	root.add_child(match)
	await process_frame
	for controller in match.controllers:
		controller.progression.level = ColonyProgression.MAX_LEVEL
		controller.nest.apply_level(ColonyProgression.MAX_LEVEL)
		while controller.get_army_size() < 60:
			var index: int = controller.get_army_size()
			var angle: float = TAU * float(index % 30) / 30.0
			var radius: float = 95.0 + floorf(float(index) / 30.0) * 45.0
			var spawn_position: Vector2 = (
				controller.commander.global_position + Vector2.from_angle(angle) * radius
			)
			if controller.spawn_unit(&"soldier", spawn_position) == null:
				_fail("Could not fill a colony to its 60-minion capacity")
				return

	var stats: Dictionary = match.get_stream_stats()
	if int(stats.get("scheduled_minions", 0)) < TARGET_MINIONS:
		_fail("Not all crowded minions were registered with the staggered scheduler")
		return
	for controller in match.controllers:
		for unit in controller.units:
			if unit.definition.role != &"commander" and unit.is_physics_processing():
				_fail("A minion still owns an independent physics callback")
				return

	var started_at: int = Time.get_ticks_usec()
	var starting_steps: int = int(stats.get("swarm_simulation_steps", 0))
	for _frame in SAMPLE_PHYSICS_FRAMES:
		await physics_frame
	var elapsed_usec: int = Time.get_ticks_usec() - started_at
	stats = match.get_stream_stats()
	var completed_steps: int = int(stats.get("swarm_simulation_steps", 0)) - starting_steps
	var minimum_expected_steps: int = roundi(
		float(SAMPLE_PHYSICS_FRAMES * match.controllers.size()) * 0.90
	)
	if completed_steps < minimum_expected_steps:
		_fail("The fixed swarm scheduler fell below its expected 20 Hz cadence")
		return
	if int(stats.get("interest_targets", 0)) != match.controllers.size():
		_fail("The dedicated server is not streaming authority around every colony")
		return
	if int(stats.get("desired_chunks", 0)) > int(stats.get("resident_chunk_limit", 0)):
		_fail("Predicted warm chunks exceeded the multiplayer resident limit")
		return
	print(
		(
			"PASS swarm_crowd_stress_test minions=%d avg_frame_usec=%d bucket_steps=%d visual_projectiles=%d logical_projectiles=%d"
			% [
				int(stats.get("scheduled_minions", 0)),
				roundi(float(elapsed_usec) / float(SAMPLE_PHYSICS_FRAMES)),
				completed_steps,
				int(stats.get("active_projectiles", 0)),
				int(stats.get("logical_projectiles", 0)),
			]
		)
	)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
