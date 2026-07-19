extends SceneTree

const REQUIRED_RESOURCES: Array[String] = [
	"res://gameplay/match/match_controller.gd",
	"res://gameplay/world/world_stream_manager.gd",
	"res://gameplay/world/world_depth_policy.gd",
	"res://gameplay/presentation/match_presentation_adapter.gd",
	"res://ui/hud.gd",
	"res://ui/minimap.gd",
	"res://ui/main_menu.gd",
	"res://ui/region_selector_panel.gd",
	"res://ui/auth_panel.gd",
	"res://ui/legal_gate_panel.gd",
	"res://network/backend_runtime_config.gd",
	"res://network/supabase_auth_client.gd",
	"res://network/supabase_data_client.gd",
	"res://network/region_probe_service.gd",
	"res://network/rivet_matchmaking_client.gd",
	"res://scenes/main_menu.tscn",
	"res://scenes/main_game.tscn",
	"res://scenes/server_game.tscn",
]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for resource_path in REQUIRED_RESOURCES:
		var resource: Resource = ResourceLoader.load(resource_path)
		if resource == null:
			_failures.append("Failed to load: %s" % resource_path)

	var world_stream := WorldStreamManager.new()
	if not world_stream is Node2D:
		_failures.append("WorldStreamManager must inherit Node2D")
	world_stream.free()

	var match_controller := MatchController.new()
	if not match_controller is Node2D:
		_failures.append("MatchController must inherit Node2D")
	match_controller.free()

	if _failures.is_empty():
		print("PHASE_04_5_1_COMPILE_SMOKE_OK")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)
