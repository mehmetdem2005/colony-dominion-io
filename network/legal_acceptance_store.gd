class_name LegalAcceptanceStore
extends RefCounted

const MANIFEST_PATH: String = "res://legal/legal_manifest.json"
const ACCEPTANCE_PATH: String = "user://legal_acceptances.cfg"

var manifest: Dictionary = {}
var acceptances: Dictionary = {}


func load_all() -> void:
	manifest.clear()
	acceptances.clear()
	if FileAccess.file_exists(MANIFEST_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if parsed is Dictionary:
			manifest = parsed
	var config := ConfigFile.new()
	if config.load(ACCEPTANCE_PATH) != OK:
		return
	for document_id in manifest.keys():
		acceptances[document_id] = {
			"version": String(config.get_value(document_id, "version", "")),
			"accepted": bool(config.get_value(document_id, "accepted", false)),
			"accepted_at": String(config.get_value(document_id, "accepted_at", "")),
		}


func has_required_acceptances() -> bool:
	for document_id in manifest.keys():
		var document: Dictionary = manifest[document_id]
		if not bool(document.get("required", false)):
			continue
		if not is_currently_accepted(String(document_id)):
			return false
	return true


func is_currently_accepted(document_id: String) -> bool:
	var document: Dictionary = manifest.get(document_id, {})
	var acceptance: Dictionary = acceptances.get(document_id, {})
	return (
		bool(acceptance.get("accepted", false))
		and String(acceptance.get("version", "")) == String(document.get("version", ""))
	)


func record_acceptances(values: Dictionary) -> Error:
	var config := ConfigFile.new()
	config.load(ACCEPTANCE_PATH)
	var timestamp: String = Time.get_datetime_string_from_system(true, true)
	for document_id in manifest.keys():
		var accepted: bool = bool(values.get(document_id, false))
		var document: Dictionary = manifest[document_id]
		config.set_value(document_id, "version", String(document.get("version", "")))
		config.set_value(document_id, "accepted", accepted)
		config.set_value(document_id, "accepted_at", timestamp if accepted else "")
		acceptances[document_id] = {
			"version": String(document.get("version", "")),
			"accepted": accepted,
			"accepted_at": timestamp if accepted else "",
		}
	return config.save(ACCEPTANCE_PATH)


func get_document_text(document_id: String) -> String:
	var document: Dictionary = manifest.get(document_id, {})
	var path: String = String(document.get("path", ""))
	return (
		FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "Belge bulunamadı."
	)


func build_remote_rows(
	user_id: String, app_version: String, locale: String = "tr-TR"
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if user_id.is_empty():
		return rows
	for document_id in manifest.keys():
		var document: Dictionary = manifest[document_id]
		var acceptance: Dictionary = acceptances.get(document_id, {})
		if not bool(acceptance.get("accepted", false)):
			continue
		(
			rows
			. append(
				{
					"user_id": user_id,
					"document_type": String(document_id),
					"document_version": String(document.get("version", "")),
					"locale": locale,
					"accepted": true,
					"accepted_at": String(acceptance.get("accepted_at", "")),
					"app_version": app_version,
				}
			)
		)
	return rows
