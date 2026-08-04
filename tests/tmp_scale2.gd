extends Node

var _match: MatchController = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load("res://scenes/server_game.tscn") as PackedScene
	_match = scene.instantiate() as MatchController
	get_tree().root.add_child(_match)
	await get_tree().process_frame
	for controller_variant in _match.controllers:
		var controller := controller_variant as ColonyController
		if is_instance_valid(controller) and controller.progression != null:
			controller.progression.level = ColonyProgression.MAX_LEVEL
	print("per_colony,units,build_10_teams_ms,per_team_us,phys_ms")
	for per_colony in [20, 40, 60]:
		for controller_variant in _match.controllers:
			var controller := controller_variant as ColonyController
			if not is_instance_valid(controller):
				continue
			var anchor: Vector2 = (
				controller.nest.global_position if is_instance_valid(controller.nest) else Vector2.ZERO
			)
			while controller.units.size() < per_colony:
				if controller.spawn_unit(&"soldier", anchor + Vector2(randf_range(-900.0, 900.0), randf_range(-900.0, 900.0))) == null:
					break
		for i in 20:
			await get_tree().physics_frame
		var units := 0
		for controller_variant in _match.controllers:
			var controller := controller_variant as ColonyController
			if is_instance_valid(controller):
				units += controller.units.size()
		var iterations := 20
		var start := Time.get_ticks_usec()
		for i in iterations:
			for team in _match.controllers.size():
				_match.build_network_snapshot_for_team(team)
		var per_batch_us := float(Time.get_ticks_usec() - start) / float(iterations)
		# physics frame cost with the full population simulating
		var phys_start := Time.get_ticks_usec()
		for i in 30:
			await get_tree().physics_frame
		var phys_ms := float(Time.get_ticks_usec() - phys_start) / 30.0 / 1000.0
		print("%d,%d,%.2f,%.0f,%.2f" % [per_colony, units, per_batch_us / 1000.0, per_batch_us / 10.0, phys_ms])
	get_tree().quit(0)
