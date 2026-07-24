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
	# The key must be identical on every launch or the encrypted session can't be
	# decrypted and the player is silently signed out each time they reopen the
	# app. OS.get_unique_id() is read very early at startup and can come back
	# empty/inconsistent on Android, so it is deliberately NOT part of the key.
	# The file already lives in the app-private sandbox (user://), so a stable
	# salt + app name is sufficient protection at rest.
	var project_name: String = String(
		ProjectSettings.get_setting("application/config/name", "Colony Dominion.io")
	)
	var context: String = "%s|%s" % [PASSWORD_SALT, project_name]
	return context.sha256_text()
