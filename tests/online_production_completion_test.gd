extends SceneTree

# Release gate for elimination recovery and safe-area UI behavior on Android.
# Project-level mobile settings are validated by tools/validate_online_release.py because
# project.godot is not exposed as a res:// runtime resource in dedicated-server tests.

const REQUIRED_FILES: Array[String] = [
	"res://network/reconnect_session_store.gd",
	"res://network/secure_local_vault.gd",
	"res://network/rivet_game_transport.gd",
	"res://autoload/rivet_online_services.gd",
	"res://tools/online_soak_client.gd",
	"res://scenes/online_soak_client.tscn",
	"res://ui/main_menu_layout_guard.gd",
	"res://ui/hud_elimination_lifecycle.gd",
	"res://ui/main_menu_modal_visibility.gd",
	"res://ui/colony_ui_kit.gd",
	"res://ui/legal_consent_card.gd",
	"res://backend/rivet-control/src/auth-confirmation-page.ts",
	"res://backend/supabase/email_templates/confirmation.html",
	"res://backend/rivet-control/src/game-server-actor.ts",
	"res://backend/rivet-control/src/rivet-native-allocator.ts",
	"res://backend/rivet-control/src/startup-canary.ts",
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
	_validate_consent_and_auth_confirmation(failures)
	_validate_google_oauth_and_bot_backfill(failures)
	var config: String = FileAccess.get_file_as_string("res://config/backend_config.json")
	if not config.contains(BUILD_ID) or not config.contains('"protocol_version": 4'):
		failures.append("Client backend configuration is not pinned to Phase 05.5")
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
	for marker in [
		"gameServer.create", "getGatewayUrl", 'transport: "websocket"', "createInRegion"
	]:
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
		failures.append("Offline HUD must retain the local elimination lifecycle controller")
	var online_hud := FileAccess.get_file_as_string("res://ui/online_match_hud.gd")
	for marker in ["_apply_responsive_layout", "set_lifecycle_state", "_layout_portrait_controls"]:
		if not online_hud.contains(marker):
			failures.append("Online HUD lifecycle/layout is missing: %s" % marker)
	if online_hud.contains("Vector2(1092.0, 528.0)"):
		failures.append("Online HUD must not return to the fixed 1280x720 control layout")
	var online_client := FileAccess.get_file_as_string(
		"res://gameplay/network/online_match_client.gd"
	)
	for marker in ["_local_nest", "_refresh_local_lifecycle", "_set_camera_anchor"]:
		if not online_client.contains(marker):
			failures.append("Online elimination recovery is missing: %s" % marker)


func _validate_google_oauth_and_bot_backfill(failures: PackedStringArray) -> void:
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
	var policy := FileAccess.get_file_as_string(
		"res://backend/rivet-control/src/matchmaking-policy.ts"
	)
	for marker in ["bot_backfill", "full_human_lobby", "waitRemainingMs"]:
		if not policy.contains(marker):
			failures.append("Bot backfill policy is missing: %s" % marker)
	var actor := FileAccess.get_file_as_string(
		"res://backend/rivet-control/src/game-server-actor.ts"
	)
	for marker in ["BOT_COUNT", "HUMAN_PLAYER_COUNT", 'RANKED_MATCH: state.ranked ? "1" : "0"']:
		if not actor.contains(marker):
			failures.append("Dedicated bot authority is missing: %s" % marker)


func _validate_consent_and_auth_confirmation(failures: PackedStringArray) -> void:
	var legal_panel := FileAccess.get_file_as_string("res://ui/legal_gate_panel.gd")
	for marker in ["LegalConsentCard", "_update_continue_state", "ONAYLARI KAYDET VE DEVAM ET"]:
		if not legal_panel.contains(marker):
			failures.append("Professional consent flow is missing: %s" % marker)
	if legal_panel.contains("CheckBox.new()"):
		failures.append("Consent flow must not use tiny default checkboxes")
	var control_server := FileAccess.get_file_as_string(
		"res://backend/rivet-control/src/server-full-online.ts"
	)
	if not control_server.contains("/v1/auth/confirmed"):
		failures.append("Public auth confirmation page route is missing")
	var confirmation_template := FileAccess.get_file_as_string(
		"res://backend/supabase/email_templates/confirmation.html"
	)
	if not confirmation_template.contains("{{ .ConfirmationURL }}"):
		failures.append("Supabase confirmation template must retain ConfirmationURL")
