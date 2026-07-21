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
			"sign_in_refresh_token",
			"POLL_TIMEOUT_SECONDS",
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
			"refresh_token: null",
			"cache-control",
			'requiredEnvironment("SUPABASE_URL")',
			"/functions/v1/oauth-google-handoff",
			"functionBaseUrl()",
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
	_assert_contains(
		"res://backend/supabase/migrations/202607210006_google_oauth_handoffs.sql",
		["enable row level security", "revoke all", "expires_at", "secret_hash"],
		failures
	)
	_assert_contains(
		"res://tools/deploy_supabase_staging.py",
		[
			"external_google_enabled",
			"GOOGLE_OAUTH_CLIENT_ID",
			"google_callback_pattern",
			"smtp.resend.com",
			"RESEND_API_KEY",
		],
		failures
	)
	_assert_contains(
		"res://backend/rivet-control/src/matchmaking-policy.ts",
		[
			"minimumHumanPlayers",
			"bot_backfill",
			"full_human_lobby",
			"waitRemainingMs",
		],
		failures,
		false
	)
	_assert_contains(
		"res://backend/rivet-control/src/server-full-online.ts",
		[
			"BOT_BACKFILL_WAIT_SECONDS",
			"evaluateMatchmakingWindow",
			"bot_backfill_seconds_remaining",
		],
		failures
	)
	_assert_contains(
		"res://backend/rivet-control/src/game-server-actor.ts",
		["BOT_COUNT", "HUMAN_PLAYER_COUNT", 'state.ranked ? "1" : "0"'],
		failures
	)
	_assert_contains(
		"res://gameplay/network/authoritative_command_router.gd",
		["set_display_name(display_name)", "assign_peer_to_available_team"],
		failures
	)
	_assert_contains(
		"res://network/game_transport.gd",
		[
			"trusted_display_name",
			"assign_peer_to_available_team(peer_id, trusted_display_name)",
		],
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

	var full_human := (
		NetworkProtocol
		. normalize_assignment(
			{
				"human_players": 10,
				"bot_players": 0,
				"ranked": true,
			}
		)
	)
	if int(full_human.get("human_players", 0)) != 10:
		failures.append("Full-human assignment metadata was not normalized")
	var bot_match := (
		NetworkProtocol
		. normalize_assignment(
			{
				"human_players": 1,
				"bot_players": 9,
				"ranked": false,
			}
		)
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
