extends SceneTree

const REQUIRED_FILES: Array[String] = [
	"res://network/reconnect_session_store.gd",
	"res://network/secure_local_vault.gd",
	"res://network/rivet_game_transport.gd",
	"res://autoload/rivet_online_services.gd",
	"res://tools/online_soak_client.gd",
	"res://scenes/online_soak_client.tscn",
	"res://backend/rivet-control/src/game-server-actor.ts",
	"res://backend/rivet-control/src/rivet-native-allocator.ts",
	"res://backend/rivet-control/src/startup-canary.ts",
	"res://backend/observability/prometheus-alerts.yml",
	"res://backend/supabase/migrations/202607190004_ranked_schema.sql",
	"res://backend/supabase/migrations/202607190005_authoritative_ranked_results.sql",
]
const BUILD_ID: String = "PHASE-05.4-RIVET-FULL-ONLINE"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for path in REQUIRED_FILES:
		if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
			failures.append("Missing production file: %s" % path)
	if NetworkProtocol.VERSION != 4:
		failures.append("Network protocol must be version 4")
	if NetworkProtocol.DEFAULT_MAX_PLAYERS != 10:
		failures.append("Online capacity must match the ten colony slots")
	_validate_mobile_input_and_orientation(failures)
	var config: String = FileAccess.get_file_as_string("res://config/backend_config.json")
	if not config.contains(BUILD_ID) or not config.contains('"protocol_version": 4'):
		failures.append("Client backend configuration is not pinned to Phase 05.4")
	var base_transport: String = FileAccess.get_file_as_string("res://network/game_transport.gd")
	for marker in [
		"resume_persisted_session",
		"_metric_reconnect_success_total",
		"RANKED_MATCH",
	]:
		if not base_transport.contains(marker):
			failures.append("Game transport is missing: %s" % marker)
	var rivet_transport: String = FileAccess.get_file_as_string(
		"res://network/rivet_game_transport.gd"
	)
	for marker in ["WebSocketMultiplayerPeer", "NETWORK_TRANSPORT", "create_client"]:
		if not rivet_transport.contains(marker):
			failures.append("Rivet transport is missing: %s" % marker)
	var allocator: String = FileAccess.get_file_as_string(
		"res://backend/rivet-control/src/rivet-native-allocator.ts"
	)
	for marker in ["gameServer.create", "getGatewayUrl", 'transport: "websocket"']:
		if not allocator.contains(marker):
			failures.append("Rivet-native allocator is missing: %s" % marker)
	if (
		allocator.contains("RIVET_ALLOCATOR_CLOUD_TOKEN")
		or allocator.contains("RIVET_ALLOCATOR_URL")
	):
		failures.append("External allocator credentials are forbidden in the Rivet-only runtime")
	var ranked_sql: String = FileAccess.get_file_as_string(
		"res://backend/supabase/migrations/202607190005_authoritative_ranked_results.sql"
	)
	for marker in ["pg_advisory_xact_lock", "ratings_processed_at", "rating_history"]:
		if not ranked_sql.contains(marker):
			failures.append("Ranked SQL is missing: %s" % marker)
	if failures.is_empty():
		print("PASS online_production_completion_test")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_mobile_input_and_orientation(failures: PackedStringArray) -> void:
	var touch_emulation: bool = bool(
		ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", false)
	)
	if not touch_emulation:
		failures.append("Android touch-to-button mouse emulation must remain enabled")
	var orientation: int = int(ProjectSettings.get_setting("display/window/handheld/orientation", -1))
	if orientation != DisplayServer.SCREEN_SENSOR:
		failures.append("Android orientation must remain in sensor mode")
	var viewport_width: int = int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var viewport_height: int = int(
		ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	)
	if viewport_width <= 0 or viewport_width != viewport_height:
		failures.append("Portrait and landscape support requires a square base viewport")
	var stretch_aspect: String = String(
		ProjectSettings.get_setting("display/window/stretch/aspect", "")
	)
	if stretch_aspect != "expand":
		failures.append("Portrait and landscape support requires stretch aspect expand")
