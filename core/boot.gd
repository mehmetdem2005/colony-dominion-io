extends Control

const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const SERVER_SCENE_PATH: String = "res://scenes/server_game.tscn"
const SOAK_CLIENT_SCENE_PATH: String = "res://scenes/online_soak_client.tscn"
const BUILD_ID: String = "PHASE-05.4-RIVET-FULL-ONLINE"


func _ready() -> void:
	print("[Colony Dominion] Build: %s" % BUILD_ID)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var target_path: String = MAIN_MENU_SCENE_PATH
	if "--soak-client" in OS.get_cmdline_user_args():
		target_path = SOAK_CLIENT_SCENE_PATH
	elif _is_headless_server():
		target_path = SERVER_SCENE_PATH
	call_deferred("_change_scene", target_path)


func _change_scene(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		push_error("Startup scene was not found: %s" % scene_path)
		get_tree().quit(1)
		return
	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_error("Startup scene could not be loaded: %s" % scene_path)
		get_tree().quit(1)
		return
	var error: Error = get_tree().change_scene_to_packed(scene)
	if error != OK:
		push_error("Startup scene transition failed: %s" % error_string(error))
		get_tree().quit(1)


func _is_headless_server() -> bool:
	return (
		OS.has_feature("dedicated_server")
		or DisplayServer.get_name() == "headless"
		or "--server" in OS.get_cmdline_user_args()
	)
