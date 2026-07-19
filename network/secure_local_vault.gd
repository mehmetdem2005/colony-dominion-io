class_name SecureLocalVault
extends RefCounted

const PASSWORD_SALT: String = "colony-dominion-local-vault-v1"


static func write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open_encrypted_with_pass(path, FileAccess.WRITE, _password())
	if file == null:
		push_warning("Secure local vault could not open for write: %s" % path)
		return false
	file.store_string(JSON.stringify(value))
	file.flush()
	return file.get_error() == OK


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open_encrypted_with_pass(path, FileAccess.READ, _password())
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


static func remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _password() -> String:
	var project_name: String = String(
		ProjectSettings.get_setting("application/config/name", "Colony Dominion.io")
	)
	var device_id: String = OS.get_unique_id().strip_edges()
	if device_id.is_empty():
		device_id = "%s:%s" % [OS.get_name(), OS.get_processor_name()]
	var context: String = "%s|%s|%s" % [PASSWORD_SALT, project_name, device_id]
	return context.sha256_text()
