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
	"res://network/edgegap_matchmaking_client.gd",
	"res://scenes/main_menu.tscn",
	"res://scenes/main_game.tscn",
	"res://scenes/server_game.tscn",
]

const NODE2D_SCRIPT_PATHS: Array[String] = [
	"res://gameplay/match/match_controller.gd",
	"res://gameplay/world/world_stream_manager.gd",
]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for resource_path in REQUIRED_RESOURCES:
		_validate_resource(resource_path)

	for script_path in NODE2D_SCRIPT_PATHS:
		_validate_node2d_script(script_path)

	_finish()


func _validate_resource(resource_path: String) -> void:
	var resource: Resource = ResourceLoader.load(resource_path)
	if resource == null:
		_failures.append("Failed to load: %s" % resource_path)
		return

	if resource is Script:
		var script := resource as Script
		if not script.can_instantiate():
			_failures.append("Script cannot instantiate: %s" % resource_path)


func _validate_node2d_script(script_path: String) -> void:
	var resource: Resource = ResourceLoader.load(script_path)
	if not resource is Script:
		_failures.append("Expected Script resource: %s" % script_path)
		return

	var script := resource as Script
	if not script.can_instantiate():
		return

	var native_base: StringName = script.get_instance_base_type()
	if native_base != &"Node2D":
		_failures.append(
			"%s must inherit Node2D, found native base: %s" % [script_path, native_base]
		)


func _finish() -> void:
	if _failures.is_empty():
		print("PHASE_04_5_1_COMPILE_SMOKE_OK")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)
