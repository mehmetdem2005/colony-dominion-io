@tool
extends SceneTree


func _initialize() -> void:
	var settings: EditorSettings = EditorInterface.get_editor_settings()
	var android_sdk: String = OS.get_environment("ANDROID_SDK_ROOT").strip_edges()
	var java_home: String = OS.get_environment("JAVA_HOME").strip_edges()
	var debug_keystore: String = (
		OS.get_environment("GODOT_ANDROID_KEYSTORE_DEBUG_PATH").strip_edges()
	)
	if android_sdk.is_empty() or not DirAccess.dir_exists_absolute(android_sdk):
		push_error("ANDROID_SDK_ROOT is missing or invalid: %s" % android_sdk)
		quit(2)
		return
	if java_home.is_empty() or not DirAccess.dir_exists_absolute(java_home):
		push_error("JAVA_HOME is missing or invalid: %s" % java_home)
		quit(3)
		return
	if debug_keystore.is_empty() or not FileAccess.file_exists(debug_keystore):
		push_error("Debug keystore is missing: %s" % debug_keystore)
		quit(4)
		return
	settings.set_setting("export/android/android_sdk_path", android_sdk)
	settings.set_setting("export/android/java_sdk_path", java_home)
	settings.set_setting("export/android/debug_keystore", debug_keystore)
	settings.set_setting("export/android/debug_keystore_user", "androiddebugkey")
	settings.set_setting("export/android/debug_keystore_pass", "android")
	settings.save()
	print("ANDROID_CI_EDITOR_SETTINGS_OK")
	quit(0)
