extends SceneTree

const SERVER_MATCH_SCENE_PATH: String = "res://scenes/server_game.tscn"
const MATCH_EVENT_HUB_SCRIPT_PATH: String = "res://gameplay/presentation/match_event_hub.gd"

const REQUIRED_BOUNDARY_SERVICES: Array[String] = [
	"res://gameplay/network/authoritative_command_router.gd",
	"res://gameplay/input/local_command_input_source.gd",
	"res://gameplay/colony/swarm_simulation_scheduler.gd",
	"res://gameplay/colony/colony_gather_service.gd",
	"res://gameplay/presentation/match_event_hub.gd",
	"res://gameplay/presentation/match_presentation_adapter.gd",
	"res://ui/hud_event_binder.gd",
	"res://ui/hud_layout_context.gd",
	"res://ui/hud_responsive_layout.gd",
	"res://gameplay/world/world_stream_read_model.gd",
	"res://gameplay/world/world_collision_activation_guard.gd",
]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	for service_path in REQUIRED_BOUNDARY_SERVICES:
		if not ResourceLoader.exists(service_path, "Script"):
			_fail("Missing architecture boundary service: %s" % service_path)
			return

	var match_source: String = FileAccess.get_file_as_string(
		"res://gameplay/match/match_controller.gd"
	)
	if match_source.contains("Input.is_action_"):
		_fail("MatchController still polls raw input instead of using the input adapter")
		return
	if (
		match_source.contains("var _peer_to_team")
		or match_source.contains("var _command_rate_by_peer")
	):
		_fail("MatchController still owns network session tables")
		return
	if match_source.contains("ColonyHUD") or match_source.contains("ColonyMinimap"):
		_fail("Gameplay composition root still depends on a concrete UI implementation")
		return

	var colony_source: String = FileAccess.get_file_as_string(
		"res://gameplay/colony/colony_controller.gd"
	)
	if colony_source.contains("var _swarm_buckets"):
		_fail("ColonyController still owns swarm scheduler storage")
		return
	if colony_source.contains("var _active_resource_target"):
		_fail("ColonyController still owns gather workflow state")
		return

	var project_source: String = FileAccess.get_file_as_string("res://project.godot")
	if project_source.contains("EventBus="):
		_fail("Global match EventBus autoload is still enabled")
		return

	var hub_script: Script = load(MATCH_EVENT_HUB_SCRIPT_PATH) as Script
	var hub_a: Node = hub_script.new() as Node
	var hub_b: Node = hub_script.new() as Node
	var deliveries: Array[int] = [0]
	hub_a.connect("toast_requested", func(_message: String) -> void: deliveries[0] += 1)
	hub_b.emit_signal("toast_requested", "isolated")
	if deliveries[0] != 0:
		_fail("Match-scoped event hubs leaked events across match instances")
		return
	hub_a.emit_signal("toast_requested", "local")
	if deliveries[0] != 1:
		_fail("Match-scoped event hub failed to deliver its local event")
		return

	var server_match_scene: PackedScene = load(SERVER_MATCH_SCENE_PATH) as PackedScene
	var match: Node = server_match_scene.instantiate()
	if match == null:
		_fail("Server composition root could not be instantiated")
		return
	root.add_child(match)
	await process_frame
	if not is_instance_valid(match.get("events")):
		_fail("Match composition root did not create a scoped event hub")
		return
	if match.get("_command_router") == null:
		_fail("Match composition root did not create the authoritative command router")
		return
	var controllers: Array = match.get("controllers") as Array
	var first_controller: Node = controllers[0] as Node
	if first_controller.get("_swarm_scheduler") == null:
		_fail("Colony aggregate did not create the swarm scheduler service")
		return
	if first_controller.get("_gather_service") == null:
		_fail("Colony aggregate did not create the gather workflow service")
		return

	print("PASS architecture_boundaries_test services=%d" % REQUIRED_BOUNDARY_SERVICES.size())
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
