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
		var confirmation_url := "%s/functions/v1/auth-confirmed" % base_url
		if not confirmation_url.begins_with("https://"):
			failures.append("Auth confirmation URL must use HTTPS")
		if "localhost" in confirmation_url.to_lower():
			failures.append("Auth confirmation URL must not use localhost")
		if not confirmation_url.ends_with("/functions/v1/auth-confirmed"):
			failures.append("Auth confirmation URL must use the Supabase Edge Function")

	_assert_source_contains(
		"res://network/supabase_auth_client.gd",
		["redirect_to=", "resend_signup_confirmation", '_auth_endpoint("signup", redirect_url)'],
		failures
	)
	_assert_source_contains(
		"res://ui/auth_panel.gd",
		["OnlineServices.config.supabase_url", "/functions/v1/auth-confirmed"],
		failures
	)
	_assert_source_contains(
		"res://ui/legal_gate_panel.gd",
		["LegalConsentCard", "_update_continue_state", "ONAYLARI KAYDET VE DEVAM ET"],
		failures
	)
	var legal_source := FileAccess.get_file_as_string("res://ui/legal_gate_panel.gd")
	if legal_source.contains("CheckBox.new()"):
		failures.append("Consent UI must not regress to tiny default checkboxes")
	_assert_source_contains(
		"res://backend/supabase/functions/auth-confirmed/index.ts",
		["Deno.serve", "E-posta adresin doğrulandı", "cache-control"],
		failures
	)
	_assert_source_contains(
		"res://backend/supabase/email_templates/confirmation.html",
		["{{ .ConfirmationURL }}", "E-POSTAYI DOĞRULA"],
		failures
	)
	_assert_source_contains(
		"res://tools/deploy_supabase_staging.py",
		["functions/v1/auth-confirmed", "uri_allow_list", "localhost_removed"],
		failures
	)
	_assert_source_contains(
		"res://.github/workflows/deploy-supabase-staging.yml",
		["functions deploy auth-confirmed", "--no-verify-jwt"],
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
