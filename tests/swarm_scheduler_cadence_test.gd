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
	await get_tree().process_frame
	var controller: ColonyController = match.controllers[0]
	var before: Dictionary = controller.get_swarm_scheduler_stats()
	for _frame in 30:
		controller._advance_swarm_scheduler(1.0 / 30.0)
	var after: Dictionary = controller.get_swarm_scheduler_stats()
	var simulated_steps: int = (
		int(after.get("simulation_steps", 0)) - int(before.get("simulation_steps", 0))
	)
	if simulated_steps < 59 or simulated_steps > 61:
		_fail("30 FPS input did not preserve the three-bucket 20 Hz cadence")
		return

	var before_burst_steps: int = int(after.get("simulation_steps", 0))
	controller._advance_swarm_scheduler(0.50)
	var after_burst: Dictionary = controller.get_swarm_scheduler_stats()
	var burst_steps: int = int(after_burst.get("simulation_steps", 0)) - before_burst_steps
	if burst_steps > ColonyController.SWARM_MAX_BUCKET_STEPS_PER_FRAME:
		_fail("A long frame exceeded the bounded catch-up budget")
		return
	if float(after_burst.get("dropped_time", 0.0)) <= 0.0:
		_fail("A long frame did not report its deliberately discarded backlog")
		return
	print(
		(
			"PASS swarm_scheduler_cadence_test steps_30fps=%d burst_steps=%d"
			% [simulated_steps, burst_steps]
		)
	)
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
