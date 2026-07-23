extends "res://autoload/online_services.gd"


func refresh_region_catalog() -> void:
	# Edgegap deploys the game server on the edge node nearest the player
	# automatically, so there is no region catalog to fetch and no manual region
	# selection. Just refresh the local probe (best-effort, cosmetic).
	if _catalog_refresh_in_progress:
		return
	_catalog_refresh_in_progress = true
	probe_regions()
	_catalog_refresh_in_progress = false


func _normalize_regions(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	var seen: Dictionary = {}
	var fallback_probe_url: String = ""
	if matchmaking.is_configured():
		fallback_probe_url = QuerySafeUrl.append_path(
			config.rivet_control_base_url, "/v1/health/ping"
		)
	for region_variant in value:
		if not region_variant is Dictionary:
			continue
		var region: Dictionary = region_variant
		var region_id: String = String(region.get("id", "")).strip_edges().to_lower()
		if region_id.is_empty() or seen.has(region_id):
			continue
		var enabled: bool = bool(region.get("enabled", true))
		var probe_url: String = String(region.get("probe_url", "")).strip_edges()
		if (
			not probe_url.begins_with("https://")
			and not (OS.is_debug_build() and probe_url.begins_with("http://"))
		):
			probe_url = fallback_probe_url if enabled else ""
		seen[region_id] = true
		(
			result
			. append(
				{
					"id": region_id,
					"display_name": String(region.get("display_name", region_id)).strip_edges(),
					"short_name":
					String(region.get("short_name", region_id.to_upper())).strip_edges(),
					"probe_url": probe_url,
					"enabled": enabled,
				}
			)
		)
	return result


func _is_valid_assignment(assignment: Dictionary) -> bool:
	var validation: Dictionary = NetworkProtocol.validate_assignment(assignment)
	if not bool(validation.get("ok", false)):
		return false
	var normalized: Dictionary = validation.get("assignment", {}) as Dictionary
	var transport: String = String(normalized.get("transport", NetworkProtocol.TRANSPORT_ENET))
	if transport == NetworkProtocol.TRANSPORT_WEBSOCKET:
		var websocket_url: String = String(normalized.get("websocket_url", ""))
		return (
			websocket_url.begins_with("wss://")
			or (OS.is_debug_build() and websocket_url.begins_with("ws://"))
		)
	return (
		transport == NetworkProtocol.TRANSPORT_ENET
		and not String(normalized.get("host", "")).is_empty()
		and int(normalized.get("port", 0)) > 0
		and int(normalized.get("port", 0)) <= 65535
	)
