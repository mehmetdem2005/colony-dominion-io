extends SceneTree

const REQUIRED_RESOURCES: Array[String] = [
	"res://scenes/main_menu.tscn",
	"res://ui/main_menu.gd",
	"res://ui/region_selector_panel.gd",
	"res://ui/auth_panel.gd",
	"res://ui/legal_gate_panel.gd",
	"res://ui/network_status_overlay.gd",
	"res://network/backend_runtime_config.gd",
	"res://network/http_json_client.gd",
	"res://network/supabase_auth_client.gd",
	"res://network/supabase_data_client.gd",
	"res://network/region_probe_service.gd",
	"res://network/rivet_matchmaking_client.gd",
	"res://network/rivet_game_transport.gd",
	"res://network/legal_acceptance_store.gd",
	"res://autoload/network_session.gd",
	"res://autoload/game_session.gd",
	"res://autoload/online_services.gd",
	"res://autoload/rivet_online_services.gd",
	"res://legal/legal_manifest.json",
	"res://config/backend_config.json",
]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for resource_path in REQUIRED_RESOURCES:
		if not FileAccess.file_exists(resource_path) and not ResourceLoader.exists(resource_path):
			_failures.append("Missing online foundation resource: %s" % resource_path)

	var config_text: String = FileAccess.get_file_as_string("res://config/backend_config.json")
	var config_variant: Variant = JSON.parse_string(config_text)
	if not config_variant is Dictionary:
		_failures.append("Backend client configuration is not valid JSON")
	else:
		var config: Dictionary = config_variant
		var regions_variant: Variant = config.get("regions", [])
		if not regions_variant is Array or (regions_variant as Array).size() != 1:
			_failures.append("Client must expose only regions that are actually deployed")
		else:
			var region_variant: Variant = (regions_variant as Array)[0]
			if not region_variant is Dictionary:
				_failures.append("Deployed client region is invalid")
			else:
				var region: Dictionary = region_variant
				if String(region.get("id", "")) != "eu":
					_failures.append("Current deployed region must be Europe")
				if not bool(region.get("enabled", false)):
					_failures.append("Europe region is not enabled")
				if not String(region.get("probe_url", "")).contains(
					"/request/v1/health/ping?"
				):
					_failures.append("Europe probe URL is not query-safe")
		if int(config.get("protocol_version", 0)) != 4:
			_failures.append("Client configuration is not pinned to protocol 4")
		var config_lower: String = config_text.to_lower()
		for forbidden in [
			"service_role", "sb_secret_", "database_password", "rivet_allocator_token"
		]:
			if config_lower.contains(forbidden):
				_failures.append(
					"Client configuration contains forbidden secret marker: %s" % forbidden
				)

	var project_text: String = FileAccess.get_file_as_string("res://project.godot")
	for autoload_name in [
		"NetworkSession", "GameSession", "GameTransport", "OnlineServices", "NetworkStatusOverlay"
	]:
		if not project_text.contains("%s=" % autoload_name):
			_failures.append("Missing online autoload: %s" % autoload_name)
	if not project_text.contains("rivet_game_transport.gd"):
		_failures.append("Rivet game transport is not active")
	if not project_text.contains("rivet_online_services.gd"):
		_failures.append("Rivet assignment validator is not active")

	var export_text: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	if not export_text.contains("permissions/internet=true"):
		_failures.append("Android INTERNET permission is disabled")
	if (
		export_text.contains('exclude_filter="*.json')
		or export_text.contains('exclude_filter="*.md')
	):
		_failures.append("Export preset still broadly excludes runtime JSON or legal Markdown")

	var legal_variant: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://legal/legal_manifest.json")
	)
	if not legal_variant is Dictionary:
		_failures.append("Legal document manifest is invalid")
	else:
		var legal: Dictionary = legal_variant
		for required_id in ["terms", "community_rules", "privacy_notice"]:
			var document_variant: Variant = legal.get(required_id, {})
			if not document_variant is Dictionary:
				_failures.append("Missing required legal document: %s" % required_id)
				continue
			var document: Dictionary = document_variant
			if not bool(document.get("required", false)):
				_failures.append("Legal document is not marked required: %s" % required_id)
			var path: String = String(document.get("path", ""))
			if path.is_empty() or not FileAccess.file_exists(path):
				_failures.append("Legal document content is missing: %s" % required_id)
		var analytics_variant: Variant = legal.get("analytics_consent", {})
		if (
			analytics_variant is Dictionary
			and bool((analytics_variant as Dictionary).get("required", true))
		):
			_failures.append("Optional analytics consent must not be mandatory")

	var migration_text: String = (
		FileAccess
		. get_file_as_string(
			"res://backend/supabase/migrations/202607190001_initial_online_schema.sql"
		)
		. to_lower()
	)
	for table_name in ["profiles", "player_preferences", "legal_acceptances", "matches"]:
		if not migration_text.contains(
			"alter table public.%s enable row level security" % table_name
		):
			_failures.append("RLS is missing for table: %s" % table_name)
	if not migration_text.contains("revoke all on public.matches from anon, authenticated"):
		_failures.append("Client match-result writes were not explicitly revoked")
	if not migration_text.contains("stamp_legal_acceptance"):
		_failures.append("Legal acceptance time is not server-stamped")

	var package_text: String = FileAccess.get_file_as_string(
		"res://backend/rivet-control/package.json"
	)
	if not package_text.contains('"rivetkit"'):
		_failures.append("Rivet control plane is not pinned to RivetKit")
	if package_text.contains('"@rivet-gg/api"'):
		_failures.append("Legacy Rivet Build API SDK remains in the full-online runtime")
	var auth_source: String = FileAccess.get_file_as_string(
		"res://backend/rivet-control/src/auth.ts"
	)
	if not auth_source.contains(".well-known/jwks.json"):
		_failures.append("Control plane does not verify Supabase JWTs through JWKS")

	_validate_offline_autoload_contract()
	_finish()


func _validate_offline_autoload_contract() -> void:
	var game_session: Node = root.get_node_or_null("GameSession")
	var network_session: Node = root.get_node_or_null("NetworkSession")

	if game_session == null:
		_failures.append("GameSession autoload is unavailable at runtime")
		return
	if network_session == null:
		_failures.append("NetworkSession autoload is unavailable at runtime")
		return
	if not game_session.has_method("prepare_offline_match"):
		_failures.append("GameSession does not expose prepare_offline_match")
		return

	game_session.call("prepare_offline_match")

	var mode_variant: Variant = network_session.get("mode")
	if not mode_variant is int or int(mode_variant) != 0:
		_failures.append("Offline mode depends on online services")

	var assignment_variant: Variant = network_session.get("match_assignment")
	if not assignment_variant is Dictionary:
		_failures.append("NetworkSession match assignment is not a Dictionary")
	elif not (assignment_variant as Dictionary).is_empty():
		_failures.append("Offline mode retained an online server assignment")


func _finish() -> void:
	if _failures.is_empty():
		print("PHASE_05_5_RIVET_FULL_ONLINE_FOUNDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
