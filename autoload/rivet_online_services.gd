extends "res://autoload/online_services.gd"


func _is_valid_assignment(assignment: Dictionary) -> bool:
	var validation: Dictionary = NetworkProtocol.validate_assignment(assignment)
	if not bool(validation.get("ok", false)):
		return false
	var normalized: Dictionary = validation.get("assignment", {}) as Dictionary
	var transport: String = String(
		normalized.get("transport", NetworkProtocol.TRANSPORT_ENET)
	)
	if transport == NetworkProtocol.TRANSPORT_WEBSOCKET:
		var websocket_url: String = String(normalized.get("websocket_url", ""))
		return websocket_url.begins_with("wss://") or (
			OS.is_debug_build() and websocket_url.begins_with("ws://")
		)
	return (
		transport == NetworkProtocol.TRANSPORT_ENET
		and not String(normalized.get("host", "")).is_empty()
		and int(normalized.get("port", 0)) > 0
		and int(normalized.get("port", 0)) <= 65535
	)
