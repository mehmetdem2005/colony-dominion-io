extends Node

var _match: MatchController = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GameTransport.set_process(false)
	var scene := load("res://scenes/server_game.tscn") as PackedScene
	_match = scene.instantiate() as MatchController
	get_tree().root.add_child(_match)
	await get_tree().process_frame
	for controller_variant in _match.controllers:
		var controller := controller_variant as ColonyController
		if is_instance_valid(controller) and controller.progression != null:
			controller.progression.level = ColonyProgression.MAX_LEVEL
	for controller_variant in _match.controllers:
		var controller := controller_variant as ColonyController
		if not is_instance_valid(controller):
			continue
		var anchor: Vector2 = (
			controller.nest.global_position if is_instance_valid(controller.nest) else Vector2.ZERO
		)
		while controller.units.size() < 60:
			if controller.spawn_unit(&"soldier", anchor + Vector2(randf_range(-900.0, 900.0), randf_range(-900.0, 900.0))) == null:
				break
	for i in 8:
		await get_tree().physics_frame
	var units := 0
	for controller_variant in _match.controllers:
		var controller := controller_variant as ColonyController
		if is_instance_valid(controller):
			units += controller.units.size()

	# One broadcast per real server tick, so the keyframe/summary cadence is the
	# real one instead of the same tick measured over and over.
	var samples: Array[float] = []
	var last_tick: int = -1
	while samples.size() < 60:
		await get_tree().physics_frame
		var tick: int = _match.get_server_tick()
		if tick == last_tick:
			continue
		last_tick = tick
		var start := Time.get_ticks_usec()
		for team in _match.controllers.size():
			_match.build_network_snapshot_for_team(team)
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
	samples.sort()
	var total := 0.0
	for value in samples:
		total += value
	print(
		"units=%d ticks=%d avg_ms=%.2f median_ms=%.2f p95_ms=%.2f max_ms=%.2f"
		% [units, samples.size(), total / samples.size(), samples[samples.size() / 2], samples[int(samples.size() * 0.95)], samples[samples.size() - 1]]
	)
	get_tree().quit(0)
