extends Node

# Runs as a scene, not via --script.
#
# A --script run compiles this file, and everything it preloads, before the
# autoloads exist. MatchController's own preload of colony_controller.gd
# therefore resolved to a script that could not compile — UnitCatalog was not a
# known identifier yet — and the broken result was baked into the class
# constant, so `new()` failed and the test sat there forever with no way to
# recover. Loading the scene again does not help: the poisoned constant lives
# inside the already-compiled class. Booting this as the main scene registers
# the autoloads first, which is the only ordering that makes the gameplay stack
# loadable at all.

const TARGET_MINIONS: int = 360
const SAMPLE_PHYSICS_FRAMES: int = 180


func _ready() -> void:
	_run_test.call_deferred()


func _run_test() -> void:
	var match_scene := load("res://scenes/server_game.tscn") as PackedScene
	if match_scene == null:
		_fail("Match scene could not be loaded")
		return
	var match := match_scene.instantiate() as MatchController
	if match == null:
		_fail("Match scene did not instantiate a MatchController")
		return
	get_tree().root.add_child(match)
	# In headless mode GameTransport takes the match for a dedicated server and
	# holds it disabled until players join, so nothing steps. That gate is a
	# server-lifecycle concern; this test is about the scheduler's cadence, so
	# it opens the gate itself. Without this the scheduler reported zero steps
	# and the failure read like a performance problem.
	# Assigned through a second name because a statement may not begin with the
	# `match` keyword, even when it is a variable.
	var running_match: Node = match
	running_match.process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().process_frame
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
		await get_tree().physics_frame
	var elapsed_usec: int = Time.get_ticks_usec() - started_at
	stats = match.get_stream_stats()
	var completed_steps: int = int(stats.get("swarm_simulation_steps", 0)) - starting_steps
	var minimum_expected_steps: int = roundi(
		float(SAMPLE_PHYSICS_FRAMES * match.controllers.size()) * 0.90
	)
	if completed_steps < minimum_expected_steps:
		_fail(
			(
				"The fixed swarm scheduler fell below its expected 20 Hz cadence: %d steps over %d frames for %d colonies, expected at least %d (%.1f ms per frame)"
				% [
					completed_steps,
					SAMPLE_PHYSICS_FRAMES,
					match.controllers.size(),
					minimum_expected_steps,
					float(elapsed_usec) / 1000.0 / float(SAMPLE_PHYSICS_FRAMES),
				]
			)
		)
		return
	if int(stats.get("interest_targets", 0)) != match.controllers.size():
		_fail("The dedicated server is not streaming authority around every colony")
		return
	if int(stats.get("desired_chunks", 0)) > int(stats.get("resident_chunk_limit", 0)):
		_fail(
			(
				"Predicted warm chunks exceeded the multiplayer resident limit: %d desired, limit %d, for %d interest targets"
				% [
					int(stats.get("desired_chunks", 0)),
					int(stats.get("resident_chunk_limit", 0)),
					int(stats.get("interest_targets", 0)),
				]
			)
		)
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
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
