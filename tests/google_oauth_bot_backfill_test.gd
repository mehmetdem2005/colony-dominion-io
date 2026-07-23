extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	_assert_contains(
		"res://network/supabase_oauth_handoff.gd",
		[
			"Crypto.new()",
			"OS.shell_open",
			"x-colony-oauth-secret",
			"code_challenge",
			"_active_code_verifier",
			"sign_in_pkce_code",
			"flow_type",
			"POLL_TIMEOUT_SECONDS",
		],
		failures
	)
	_assert_contains(
		"res://network/supabase_auth_client.gd",
		[
			"grant_type=pkce",
			"auth_code",
			"code_verifier",
			"PKCE_VERIFIER_PATTERN",
		],
		failures
	)
	_assert_contains(
		"res://backend/supabase/functions/oauth-google-handoff/index.ts",
		[
			"SUPABASE_SERVICE_ROLE_KEY",
			"oauth_handoffs",
			"constantTimeEqual",
			'consumed_at: "is.null"',
			"Cache-Control",
			'requiredEnvironment("SUPABASE_URL")',
			"/functions/v1/oauth-google-handoff",
			"functionBaseUrl()",
			"new Headers",
			"UTF8_ENCODER.encode",
			"Content-Disposition",
			"Content-Security-Policy",
			"randomHex",
			"flow_type",
			"pkce",
			"callback_nonce_hash",
			"auth_code",
			"tokens_in_browser",
			"code_challenge_method",
		],
		failures
	)
	var oauth_function_source := FileAccess.get_file_as_string(
		"res://backend/supabase/functions/oauth-google-handoff/index.ts"
	)
	if oauth_function_source.contains("functionBaseUrl(request)"):
		failures.append("OAuth callback URL must not be derived from the internal request URL")
	if oauth_function_source.contains("return `${url.origin}"):
		failures.append("OAuth callback URL must not use the Edge proxy origin")
	for forbidden in [
		"nonce-colony-oauth",
		"location.hash",
		'params.get("refresh_token")',
		"refresh_token: refreshToken",
		"/complete/",
		'action === "complete"',
	]:
		if oauth_function_source.contains(forbidden):
			failures.append("Implicit OAuth marker remains: %s" % forbidden)
	_assert_contains(
		"res://.github/workflows/deploy-supabase-staging.yml",
		[
			"Verify OAuth callback renders as secure UTF-8 plain text",
			"text/plain;charset=utf-8",
			"google-oauth-callback-verification.json",
			"secret_markers_absent",
			"tokens_in_browser",
			"flow_type",
		],
		failures
	)
	_assert_contains(
		"res://backend/supabase/migrations/202607210006_google_oauth_handoffs.sql",
		["enable row level security", "revoke all", "expires_at", "secret_hash"],
		failures
	)
	_assert_contains(
		"res://backend/supabase/migrations/202607220007_google_oauth_pkce_handoffs.sql",
		["flow_type", "pkce", "callback_nonce_hash", "auth_code", "single-use"],
		failures
	)
	_assert_contains(
		"res://tools/deploy_supabase_staging.py",
		["external_google_enabled", "GOOGLE_OAUTH_CLIENT_ID", "google_callback_pattern"],
		failures
	)
	_assert_contains(
		"res://backend/supabase/functions/matchmaking/index.ts",
		[
			"GAME_MAX_PLAYERS",
			"HUMAN_PLAYER_COUNT",
			"BOT_COUNT",
			"RANKED_MATCH",
			"EXPECTED_JOIN_TICKET",
		],
		failures
	)
	_assert_contains(
		"res://network/rivet_game_transport.gd",
		["_configure_server_population", "ENetMultiplayerPeer", "NETWORK_TRANSPORT"],
		failures
	)
	_assert_contains(
		"res://network/region_probe_service.gd",
		["WARMUP_SAMPLE_COUNT", "MEASURED_SAMPLE_COUNT", "_metrics.clear()"],
		failures
	)
	_assert_contains(
		"res://gameplay/network/authoritative_command_router.gd",
		["set_display_name(display_name)", "assign_peer_to_available_team"],
		failures
	)
	_assert_contains(
		"res://network/game_transport.gd",
		["trusted_display_name", "assign_peer_to_available_team(peer_id, trusted_display_name)"],
		failures
	)
	_assert_contains(
		"res://network/network_protocol.gd",
		["human_players", "bot_players", "Bot içeren maç dereceli olamaz"],
		failures
	)
	_assert_contains(
		"res://ui/auth_panel.gd", ["GOOGLE İLE DEVAM ET", "OnlineServices.sign_in_google"], failures
	)
	var auth_panel_source := FileAccess.get_file_as_string("res://ui/auth_panel.gd")
	for forbidden in [
		"sign_in_email",
		"sign_up_email",
		"resend_signup_confirmation",
		"E-posta adresi",
		"Şifre —",
		"YENİ HESAP OLUŞTUR",
	]:
		if auth_panel_source.contains(forbidden):
			failures.append("Google-only auth panel still contains: %s" % forbidden)

	var config_variant: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://config/backend_config.json")
	)
	if not config_variant is Dictionary:
		failures.append("Backend configuration is invalid JSON")
	else:
		var config: Dictionary = config_variant
		var regions_variant: Variant = config.get("regions", [])
		if not regions_variant is Array:
			failures.append("Edgegap placement targets are missing")
		else:
			var region_ids: Dictionary = {}
			for region_variant in regions_variant:
				if region_variant is Dictionary:
					var region: Dictionary = region_variant
					region_ids[String(region.get("id", ""))] = true
			for required_id in ["auto", "tr", "eu-se", "eu-central"]:
				if not region_ids.has(required_id):
					failures.append("Missing Edgegap placement target: %s" % required_id)

	var full_human := NetworkProtocol.normalize_assignment(
		{"human_players": 10, "bot_players": 0, "ranked": true}
	)
	if int(full_human.get("human_players", 0)) != 10:
		failures.append("Full-human assignment metadata was not normalized")
	var bot_match := NetworkProtocol.normalize_assignment(
		{"human_players": 1, "bot_players": 9, "ranked": false}
	)
	if int(bot_match.get("bot_players", 0)) != 9 or bool(bot_match.get("ranked", true)):
		failures.append("Bot-backfill assignment metadata was not normalized")

	if failures.is_empty():
		print("PASS google_oauth_bot_backfill_test")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _assert_contains(
	path: String, markers: Array[String], failures: PackedStringArray, require_all: bool = true
) -> void:
	var source := FileAccess.get_file_as_string(path)
	if source.is_empty():
		failures.append("Required production source is missing: %s" % path)
		return
	var matched := 0
	for marker in markers:
		if source.contains(marker):
			matched += 1
		elif require_all:
			failures.append("%s is missing marker: %s" % [path, marker])
	if not require_all and matched == 0:
		failures.append("%s contains none of the required policy markers" % path)
