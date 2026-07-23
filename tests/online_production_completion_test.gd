extends SceneTree

# Release gate for Edgegap deployment, online/offline presentation parity, and
# safe-area lifecycle behavior on Android.

const REQUIRED_FILES: Array[String] = [
	"res://network/reconnect_session_store.gd",
	"res://network/secure_local_vault.gd",
	"res://network/rivet_game_transport.gd",
	"res://network/edgegap_matchmaking_client.gd",
	"res://autoload/rivet_online_services.gd",
	"res://tools/online_soak_client.gd",
	"res://scenes/online_soak_client.tscn",
	"res://scenes/network/network_entity_proxy.tscn",
	"res://scenes/ui/hud.tscn",
	"res://ui/main_menu_layout_guard.gd",
	"res://ui/hud_elimination_lifecycle.gd",
	"res://ui/main_menu_modal_visibility.gd",
	"res://ui/colony_ui_kit.gd",
	"res://ui/legal_consent_card.gd",
	"res://backend/supabase/functions/matchmaking/index.ts",
	"res://backend/supabase/functions/oauth-google-handoff/index.ts",
	"res://backend/supabase/email_templates/confirmation.html",
	"res://deploy/edgegap/Dockerfile",
	"res://backend/observability/prometheus-alerts.yml",
	"res://backend/supabase/migrations/202607190004_ranked_schema.sql",
	"res://backend/supabase/migrations/202607190005_authoritative_ranked_results.sql",
]
const BUILD_ID: String = "PHASE-05.5-GOOGLE-BOT-BACKFILL"


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
	_validate_ui_lifecycle(failures)
	_validate_consent_and_google_auth(failures)
	_validate_edgegap_and_bot_backfill(failures)

	var config: String = FileAccess.get_file_as_string("res://config/backend_config.json")
	if not config.contains(BUILD_ID) or not config.contains('"protocol_version": 4'):
		failures.append("Client backend configuration is not pinned to the production build")
	var transport: String = FileAccess.get_file_as_string("res://network/game_transport.gd")
	for marker in [
		"resume_persisted_session",
		"_metric_reconnect_success_total",
		"RANKED_MATCH",
		"EXPECTED_JOIN_TICKET",
		"_median_sample",
	]:
		if not transport.contains(marker):
			failures.append("Game transport is missing: %s" % marker)
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


func _validate_ui_lifecycle(failures: PackedStringArray) -> void:
	var menu_scene := FileAccess.get_file_as_string("res://scenes/main_menu.tscn")
	if (
		not menu_scene.contains("MainMenuLayoutGuard")
		and not menu_scene.contains("main_menu_layout_guard.gd")
	):
		failures.append("Main menu must retain the safe-area layout guard")
	if not menu_scene.contains("main_menu_modal_visibility.gd"):
		failures.append("Main menu must hide its base panel behind modal content")
	var hud_scene := FileAccess.get_file_as_string("res://scenes/ui/hud.tscn")
	if not hud_scene.contains("hud_elimination_lifecycle.gd"):
		failures.append("Shared HUD must retain the local elimination lifecycle controller")
	var online_scene := FileAccess.get_file_as_string("res://scenes/online_game.tscn")
	if not online_scene.contains("res://scenes/ui/hud.tscn"):
		failures.append("Online game must instance the same HUD scene as offline")
	if FileAccess.file_exists("res://ui/online_match_hud.gd"):
		failures.append("Duplicate online-only HUD still exists")
	var shared_hud := FileAccess.get_file_as_string("res://ui/hud.gd")
	for marker in [
		"_apply_responsive_layout",
		"bind_online",
		"apply_online_player_state",
		"set_lifecycle_state"
	]:
		if not shared_hud.contains(marker):
			failures.append("Shared HUD online lifecycle is missing: %s" % marker)
	var online_client := FileAccess.get_file_as_string(
		"res://gameplay/network/online_match_client.gd"
	)
	for marker in [
		"_local_nest",
		"_refresh_local_lifecycle",
		"_camera_anchor == anchor",
		"get_minimap_snapshot",
	]:
		if not online_client.contains(marker):
			failures.append("Online recovery/presentation is missing: %s" % marker)


func _validate_edgegap_and_bot_backfill(failures: PackedStringArray) -> void:
	var matchmaking := FileAccess.get_file_as_string(
		"res://backend/supabase/functions/matchmaking/index.ts"
	)
	for marker in [
		"api.edgegap.com/v1",
		"ip_list",
		"REGION_TARGETS",
		"HUMAN_PLAYER_COUNT",
		"BOT_COUNT",
		"RANKED_MATCH",
		"EXPECTED_JOIN_TICKET",
	]:
		if not matchmaking.contains(marker):
			failures.append("Edgegap production contract is missing: %s" % marker)
	var transport := FileAccess.get_file_as_string("res://network/rivet_game_transport.gd")
	for marker in [
		"ENetMultiplayerPeer",
		"NETWORK_TRANSPORT",
		"_configure_server_population",
		"create_client",
	]:
		if not transport.contains(marker):
			failures.append("Direct Edgegap transport is missing: %s" % marker)
	var dockerfile := FileAccess.get_file_as_string("res://deploy/edgegap/Dockerfile")
	for marker in ["EXPOSE 20000/udp", "--headless", "colony-dominion-server.x86_64"]:
		if not dockerfile.contains(marker):
			failures.append("Edgegap image is missing: %s" % marker)


func _validate_consent_and_google_auth(failures: PackedStringArray) -> void:
	var legal_panel := FileAccess.get_file_as_string("res://ui/legal_gate_panel.gd")
	for marker in ["LegalConsentCard", "_update_continue_state", "ONAYLARI KAYDET VE DEVAM ET"]:
		if not legal_panel.contains(marker):
			failures.append("Professional consent flow is missing: %s" % marker)
	if legal_panel.contains("CheckBox.new()"):
		failures.append("Consent flow must not use tiny default checkboxes")
	var oauth_bridge := FileAccess.get_file_as_string("res://network/supabase_oauth_handoff.gd")
	for marker in ["Crypto.new()", "OS.shell_open", "x-colony-oauth-secret"]:
		if not oauth_bridge.contains(marker):
			failures.append("Google OAuth handoff is missing: %s" % marker)
	var auth_panel := FileAccess.get_file_as_string("res://ui/auth_panel.gd")
	for marker in ["GOOGLE İLE DEVAM ET", "OnlineServices.sign_in_google"]:
		if not auth_panel.contains(marker):
			failures.append("Google-only auth UI is missing: %s" % marker)
	for forbidden in ["sign_in_email", "sign_up_email", "resend_signup_confirmation"]:
		if auth_panel.contains(forbidden):
			failures.append("Google-only auth UI contains forbidden flow: %s" % forbidden)
	var confirmation_template := FileAccess.get_file_as_string(
		"res://backend/supabase/email_templates/confirmation.html"
	)
	if not confirmation_template.contains("{{ .ConfirmationURL }}"):
		failures.append("Supabase confirmation template must retain ConfirmationURL")
