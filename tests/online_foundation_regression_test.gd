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
	"res://network/edgegap_matchmaking_client.gd",
	"res://network/rivet_game_transport.gd",
	"res://network/legal_acceptance_store.gd",
	"res://autoload/network_session.gd",
	"res://autoload/game_session.gd",
	"res://autoload/online_services.gd",
	"res://autoload/rivet_online_services.gd",
	"res://legal/legal_manifest.json",
	"res://config/backend_config.json",
	"res://backend/supabase/functions/matchmaking/index.ts",
	"res://deploy/edgegap/Dockerfile",
]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for resource_path in REQUIRED_RESOURCES:
		if not FileAccess.file_exists(resource_path) and not ResourceLoader.exists(resource_path):
			_failures.append("Missing online foundation resource: %s" % resource_path)

	_validate_client_config()
	_validate_project_contract()
	_validate_legal_and_storage_contract()
	_validate_edgegap_contract()
	_validate_offline_autoload_contract()
	_finish()


func _validate_client_config() -> void:
	var config_text: String = FileAccess.get_file_as_string("res://config/backend_config.json")
	var config_variant: Variant = JSON.parse_string(config_text)
	if not config_variant is Dictionary:
		_failures.append("Backend client configuration is not valid JSON")
		return
	var config: Dictionary = config_variant
	if int(config.get("protocol_version", 0)) != NetworkProtocol.VERSION:
		_failures.append("Client and network protocol versions differ")
	var regions_variant: Variant = config.get("regions", [])
	if not regions_variant is Array:
		_failures.append("Edgegap placement targets are missing")
		return
	var region_ids: Dictionary = {}
	for region_variant in regions_variant:
		if not region_variant is Dictionary:
			continue
		var region: Dictionary = region_variant
		if not bool(region.get("enabled", false)):
			continue
		region_ids[String(region.get("id", ""))] = true
		if not bool(region.get("placement_only", false)):
			_failures.append("Edgegap target must be placement-only: %s" % region.get("id", ""))
	for required_id in ["auto", "frankfurt", "paris", "singapore"]:
		if not region_ids.has(required_id):
			_failures.append("Missing Edgegap placement target: %s" % required_id)
	var config_lower: String = config_text.to_lower()
	for forbidden in ["service_role", "sb_secret_", "database_password", "edgegap_api_token"]:
		if config_lower.contains(forbidden):
			_failures.append("Client configuration contains secret marker: %s" % forbidden)


func _validate_project_contract() -> void:
	var project_text: String = FileAccess.get_file_as_string("res://project.godot")
	for autoload_name in [
		"NetworkSession", "GameSession", "GameTransport", "OnlineServices", "NetworkStatusOverlay"
	]:
		if not project_text.contains("%s=" % autoload_name):
			_failures.append("Missing online autoload: %s" % autoload_name)
	if not project_text.contains("rivet_game_transport.gd"):
		_failures.append("ENet/WebSocket compatibility transport is not active")
	if not project_text.contains("rivet_online_services.gd"):
		_failures.append("Edgegap assignment validator wrapper is not active")
	var online_services: String = FileAccess.get_file_as_string("res://autoload/online_services.gd")
	if not online_services.contains("EdgegapMatchmakingClient"):
		_failures.append("OnlineServices is not wired to Edgegap matchmaking")

	var export_text: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	if not export_text.contains("permissions/internet=true"):
		_failures.append("Android INTERNET permission is disabled")
	if (
		export_text.contains('exclude_filter="*.json')
		or export_text.contains('exclude_filter="*.md')
	):
		_failures.append("Export preset broadly excludes runtime JSON or legal Markdown")


func _validate_legal_and_storage_contract() -> void:
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


func _validate_edgegap_contract() -> void:
	var function_source: String = FileAccess.get_file_as_string(
		"res://backend/supabase/functions/matchmaking/index.ts"
	)
	for marker in [
		"https://api.edgegap.com/v1",
		"/deploy",
		"ip_list",
		"location",
		"skip_telemetry",
		"authenticatedUserId",
		"EXPECTED_JOIN_TICKET",
	]:
		if not function_source.contains(marker):
			_failures.append("Edgegap matchmaking contract is missing: %s" % marker)
	if function_source.contains("DEV_ACCEPT_JOIN_TICKETS"):
		_failures.append("Production Edgegap deploy must not enable development ticket acceptance")
	var client_source: String = FileAccess.get_file_as_string(
		"res://network/edgegap_matchmaking_client.gd"
	)
	if client_source.contains("EDGEGAP_API_TOKEN"):
		_failures.append("Edgegap API token name leaked into the game client")


func _validate_offline_autoload_contract() -> void:
	var game_session: Node = root.get_node_or_null("GameSession")
	var network_session: Node = root.get_node_or_null("NetworkSession")
	if game_session == null or network_session == null:
		_failures.append("Offline session autoloads are unavailable")
		return
	game_session.call("prepare_offline_match")
	if int(network_session.get("mode")) != 0:
		_failures.append("Offline mode depends on online services")
	var assignment_variant: Variant = network_session.get("match_assignment")
	if not assignment_variant is Dictionary or not (assignment_variant as Dictionary).is_empty():
		_failures.append("Offline mode retained an online server assignment")


func _finish() -> void:
	if _failures.is_empty():
		print("PASS online_foundation_regression_test")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
