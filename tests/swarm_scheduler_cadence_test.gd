extends SceneTree

const MATCH_SCENE := preload("res://scenes/server_game.tscn")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var match := MATCH_SCENE.instantiate() as MatchController
	root.add_child(match)
	await process_frame
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
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
