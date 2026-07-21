extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	var config_variant: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://config/backend_config.json")
	)
	if not config_variant is Dictionary:
		failures.append("Backend config could not be parsed")
	else:
		var config := config_variant as Dictionary
		var base_url := String(config.get("supabase_url", "")).trim_suffix("/")
		var oauth_url := "%s/functions/v1/oauth-google-handoff" % base_url
		if not oauth_url.begins_with("https://"):
			failures.append("Google OAuth handoff URL must use HTTPS")
		if "localhost" in oauth_url.to_lower():
			failures.append("Google OAuth handoff URL must not use localhost")
		if not oauth_url.ends_with("/functions/v1/oauth-google-handoff"):
			failures.append("Google OAuth handoff URL must use the Supabase Edge Function")

	_assert_source_contains(
		"res://network/supabase_oauth_handoff.gd",
		[
			"OS.shell_open",
			"x-colony-oauth-secret",
			"sign_in_refresh_token",
			"POLL_TIMEOUT_SECONDS",
		],
		failures
	)
	_assert_source_contains(
		"res://ui/auth_panel.gd",
		[
			"GOOGLE İLE DEVAM ET",
			"OnlineServices.sign_in_google",
			"E-posta veya şifre formu kullanılmaz"
		],
		failures
	)
	var auth_panel_source := FileAccess.get_file_as_string("res://ui/auth_panel.gd")
	for forbidden in [
		"sign_in_email",
		"sign_up_email",
		"resend_signup_confirmation",
		"YENİ HESAP OLUŞTUR",
		"E-POSTA GİRİŞİ",
	]:
		if auth_panel_source.contains(forbidden):
			failures.append("Google-only auth UI contains forbidden flow: %s" % forbidden)
	_assert_source_contains(
		"res://ui/legal_gate_panel.gd",
		["LegalConsentCard", "_update_continue_state", "ONAYLARI KAYDET VE DEVAM ET"],
		failures
	)
	var legal_source := FileAccess.get_file_as_string("res://ui/legal_gate_panel.gd")
	if legal_source.contains("CheckBox.new()"):
		failures.append("Consent UI must not regress to tiny default checkboxes")
	_assert_source_contains(
		"res://backend/supabase/functions/oauth-google-handoff/index.ts",
		[
			"Deno.serve",
			"functionBaseUrl()",
			"/functions/v1/oauth-google-handoff",
			"cache-control",
		],
		failures
	)
	_assert_source_contains(
		"res://tools/deploy_supabase_staging.py",
		[
			"functions/v1/oauth-google-handoff",
			"external_google_enabled",
			"google_callback_pattern",
			"localhost_removed",
		],
		failures
	)
	_assert_source_contains(
		"res://.github/workflows/deploy-supabase-staging.yml",
		["functions deploy oauth-google-handoff", "--no-verify-jwt"],
		failures
	)

	if failures.is_empty():
		print("PASS auth_confirmation_flow_test")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _assert_source_contains(
	path: String, markers: Array[String], failures: PackedStringArray
) -> void:
	var source := FileAccess.get_file_as_string(path)
	if source.is_empty():
		failures.append("Required source file is missing or empty: %s" % path)
		return
	for marker in markers:
		if not source.contains(marker):
			failures.append("%s is missing marker: %s" % [path, marker])
