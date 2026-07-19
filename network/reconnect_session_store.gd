class_name ReconnectSessionStore
extends RefCounted

const SESSION_PATH: String = "user://online_reconnect_session.vault"
const FORMAT_VERSION: int = 2


func save_session(session: Dictionary) -> bool:
	var normalized: Dictionary = _normalize(session)
	if not _is_valid(normalized):
		return false
	return SecureLocalVault.write_json(SESSION_PATH, normalized)


func load_session(expected_build_id: String, expected_protocol_version: int) -> Dictionary:
	var session: Dictionary = _normalize(SecureLocalVault.read_json(SESSION_PATH))
	if not _is_valid(session):
		clear()
		return {}
	if int(session.get("protocol_version", 0)) != expected_protocol_version:
		clear()
		return {}
	if (
		not expected_build_id.is_empty()
		and String(session.get("build_id", "")) != expected_build_id
	):
		clear()
		return {}
	var now_msec: int = roundi(Time.get_unix_time_from_system() * 1000.0)
	if int(session.get("resume_until_unix_msec", 0)) <= now_msec:
		clear()
		return {}
	return session


func has_session(expected_build_id: String, expected_protocol_version: int) -> bool:
	return not load_session(expected_build_id, expected_protocol_version).is_empty()


func clear() -> void:
	SecureLocalVault.remove(SESSION_PATH)


func _normalize(value: Dictionary) -> Dictionary:
	var assignment_variant: Variant = value.get("assignment", {})
	var assignment: Dictionary = (
		NetworkProtocol.normalize_assignment(assignment_variant)
		if assignment_variant is Dictionary
		else {}
	)
	# Join tickets are single-use credentials and must never be persisted.
	assignment["join_ticket"] = ""
	return {
		"format_version": int(value.get("format_version", FORMAT_VERSION)),
		"assignment": assignment,
		"player_id": String(value.get("player_id", "")).strip_edges(),
		"display_name": String(value.get("display_name", "")).strip_edges().left(24),
		"build_id": String(value.get("build_id", "")).strip_edges(),
		"protocol_version": int(value.get("protocol_version", 0)),
		"reconnect_token": String(value.get("reconnect_token", "")).strip_edges(),
		"team_id": int(value.get("team_id", -1)),
		"resume_until_unix_msec": int(value.get("resume_until_unix_msec", 0)),
		"saved_at_unix_msec": int(value.get("saved_at_unix_msec", 0)),
	}


func _is_valid(session: Dictionary) -> bool:
	if int(session.get("format_version", 0)) != FORMAT_VERSION:
		return false
	if (
		String(session.get("player_id", "")).is_empty()
		or String(session.get("build_id", "")).is_empty()
	):
		return false
	var reconnect_token: String = String(session.get("reconnect_token", ""))
	if reconnect_token.length() < 24 or reconnect_token.length() > 256:
		return false
	if int(session.get("team_id", -1)) < 0:
		return false
	var assignment_variant: Variant = session.get("assignment", {})
	return (
		assignment_variant is Dictionary
		and bool(NetworkProtocol.validate_reconnect_assignment(assignment_variant).get("ok", false))
	)
