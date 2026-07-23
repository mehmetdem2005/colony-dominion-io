extends SceneTree

const REGISTRY_SCRIPT := preload("res://gameplay/network/network_entity_registry.gd")
const SERVER_MATCH_SCENE_PATH := "res://scenes/server_game.tscn"
const PROJECTILE_SCENE_PATH := "res://scenes/combat/projectile.tscn"
const RESOURCE_SCENE_PATH := "res://scenes/resources/resource_node.tscn"


class EntityStub:
	extends Node2D

	var network_entity_id: int = 0
	var team_id: int = 0


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var failures: Array[String] = []
	_test_registry_collision(failures)
	_test_inventory_negative_cost(failures)
	await _test_invalid_projectile_configuration(failures)
	await _test_resource_input_sanitization(failures)
	await _test_server_match_runtime_guards(failures)
	_test_source_contracts(failures)
	if failures.is_empty():
		print("PASS deep_runtime_hardening_regression_test")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _test_registry_collision(failures: Array[String]) -> void:
	var registry := REGISTRY_SCRIPT.new() as NetworkEntityRegistry
	var first := EntityStub.new()
	var second := EntityStub.new()
	root.add_child(first)
	root.add_child(second)
	var first_id: int = registry.register(first, 77)
	first.network_entity_id = first_id
	if first_id != 77:
		failures.append("Preferred entity id was not registered")
	if registry.register(second, 77) != 0:
		failures.append("A live entity id collision overwrote the registered node")
	registry.unregister(77, second)
	if registry.resolve(77) != first:
		failures.append("Unregister with the wrong expected node removed a live entity")
	first.free()
	if registry.resolve(77) != null:
		failures.append("A freed entity remained resolvable")
	var replacement_id: int = registry.register(second, 77)
	second.network_entity_id = replacement_id
	if replacement_id != 77 or registry.resolve(77) != second:
		failures.append("A retired preferred id could not be assigned safely")
	second.free()


func _test_inventory_negative_cost(failures: Array[String]) -> void:
	var inventory := ColonyInventory.new({&"seed": 10, &"nectar": 4})
	var before: Dictionary = inventory.snapshot()
	if not inventory.spend_cost({&"seed": -999, &"nectar": -3}):
		failures.append("A zero-effective cost was unexpectedly rejected")
	if inventory.snapshot() != before:
		failures.append("Negative production costs changed inventory values")


func _test_invalid_projectile_configuration(failures: Array[String]) -> void:
	var projectile_scene := load(PROJECTILE_SCENE_PATH) as PackedScene
	if projectile_scene == null:
		failures.append("Projectile scene could not be loaded")
		return
	var projectile := projectile_scene.instantiate()
	var resolver := EntityStub.new()
	var attacker := EntityStub.new()
	var target := EntityStub.new()
	root.add_child(resolver)
	root.add_child(attacker)
	root.add_child(target)
	root.add_child(projectile)
	attacker.network_entity_id = 1
	target.network_entity_id = 2
	projectile.call("configure", resolver, attacker, target, NAN, 420.0, Color.WHITE)
	if bool(projectile.get("active")):
		failures.append("Projectile accepted non-finite damage")
	projectile.call("configure", resolver, attacker, target, 10.0, -1.0, Color.WHITE)
	if bool(projectile.get("active")):
		failures.append("Projectile accepted non-positive speed")
	projectile.free()
	resolver.free()
	attacker.free()
	target.free()
	await process_frame


func _test_resource_input_sanitization(failures: Array[String]) -> void:
	var resource_scene := load(RESOURCE_SCENE_PATH) as PackedScene
	if resource_scene == null:
		failures.append("Resource scene could not be loaded")
		return
	var resource := resource_scene.instantiate()
	root.add_child(resource)
	resource.call("configure", &"seed", null, -50, NAN)
	if int(resource.get("amount")) != 1 or int(resource.get("max_amount")) != 1:
		failures.append("Resource activation did not clamp an invalid starting amount")
	resource.call("advance_simulation", NAN)
	if int(resource.get("amount")) != 1:
		failures.append("Non-finite resource simulation delta mutated state")
	resource.free()
	await process_frame


func _test_server_match_runtime_guards(failures: Array[String]) -> void:
	var server_match_scene := load(SERVER_MATCH_SCENE_PATH) as PackedScene
	if server_match_scene == null:
		failures.append("Server match scene could not be loaded")
		return
	var match_node := server_match_scene.instantiate()
	if match_node == null:
		failures.append("Server match composition root could not be instantiated")
		return
	root.add_child(match_node)
	await process_frame
	var controllers_variant: Variant = match_node.get("controllers")
	if not controllers_variant is Array or controllers_variant.is_empty():
		failures.append("Server match did not initialize colonies")
		match_node.free()
		return
	var controllers: Array = controllers_variant
	var player_controller := controllers[0] as Node
	for controller_variant in controllers:
		var active_controller := controller_variant as Node
		if not bool(active_controller.call("is_active")):
			failures.append("A live server colony was reported inactive")
	match_node.call("_check_victory")
	if bool(match_node.get("match_finished")):
		failures.append("Server match ended while multiple colonies were alive")
	var eliminated_controller := controllers[1] as Node
	eliminated_controller.set("eliminated", true)
	if bool(match_node.call("assign_peer_to_team", 99, int(eliminated_controller.get("team_id")))):
		failures.append("A peer was assigned to an eliminated colony")
	eliminated_controller.set("eliminated", false)
	player_controller.call("set_joystick_input", Vector2(NAN, 0.0))
	if player_controller.call("get_movement_input") != Vector2.ZERO:
		failures.append("Non-finite movement input reached colony simulation")
	var snapshot_variant: Variant = match_node.call("build_network_snapshot_for_team", 0, NAN)
	var snapshot: Dictionary = snapshot_variant if snapshot_variant is Dictionary else {}
	if snapshot.is_empty() or not snapshot.has("entities"):
		failures.append("Non-finite snapshot radius broke snapshot generation")
	var commander := player_controller.get("commander") as Node
	if is_instance_valid(commander):
		var health_before: float = float(commander.get("health"))
		commander.call("take_damage", NAN)
		if not is_equal_approx(float(commander.get("health")), health_before):
			failures.append("Non-finite unit damage changed health")
	match_node.free()
	await process_frame


func _test_source_contracts(failures: Array[String]) -> void:
	var contracts := {
		"res://audio/scripts/audio_system.gd":
		[
			"AudioEffectHardLimiter",
			"AudioServer.remove_bus_effect",
			"definition.positional",
		],
		"res://audio/scripts/audio_event_library.gd":
		[
			"Duplicate audio event id rejected",
		],
		"res://gameplay/colony/colony_controller.gd":
		[
			"not eliminated",
			"is_instance_valid(commander)",
			"nest.is_alive()",
			"COMMANDER_RESPAWN_RETRY_DELAY",
			"respawned_commander",
		],
		"res://gameplay/units/unit.gd":
		[
			"const ACTIVATION_RECOVERY_DIRECTIONS",
			"const ACTIVATION_RECOVERY_RINGS",
			"const MAX_WORLD_SLIDE_ITERATIONS",
		],
		"res://gameplay/world/world_stream_manager.gd":
		[
			"_prepare_runtime_prop_collision_activation(job.runtime)",
			"MAX_RESOURCE_SIMULATION_STEPS_PER_FRAME",
		],
		"res://gameplay/colony/nest.gd":
		[
			"production_queue.push_front(finished_id)",
			"PRODUCTION_RETRY_DELAY",
		],
		"res://gameplay/match/match_controller.gd":
		[
			"on_controller_commander_changed",
			"if is_instance_valid(camera_anchor):",
			"controller.eliminated",
		],
		"res://gameplay/network/network_snapshot_builder.gd":
		[
			"_build_empty",
		],
		"res://gameplay/world/streamed_world_prop.gd":
		[
			"set_stream_residency(false)",
		],
		"res://gameplay/economy/resource_node.gd":
		[
			"set_stream_residency(false)",
		],
		"res://ui/virtual_stick.gd":
		[
			"get_global_transform_with_canvas().affine_inverse()",
		],
		"res://ui/touch_action_button.gd":
		[
			"get_global_transform_with_canvas().affine_inverse()",
		],
		"res://ui/production_touch_card.gd":
		[
			"get_global_transform_with_canvas().affine_inverse()",
		],
	}
	for path_variant in contracts:
		var path: String = path_variant
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			failures.append("Could not read hardening contract source: %s" % path)
			continue
		var source: String = file.get_as_text()
		for required_variant in contracts[path]:
			var required: String = required_variant
			if source.find(required) < 0:
				failures.append("Missing hardening contract '%s' in %s" % [required, path])
