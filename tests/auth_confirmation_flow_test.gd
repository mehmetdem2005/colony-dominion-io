extends SceneTree

const URL_BUILDER := preload("res://network/query_safe_url.gd")


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
		var base_url := String(config.get("rivet_control_base_url", ""))
		var confirmation_url := URL_BUILDER.append_path(base_url, "/v1/auth/confirmed")
		if not confirmation_url.begins_with("https://"):
			failures.append("Auth confirmation URL must use HTTPS")
		if "localhost" in confirmation_url.to_lower():
			failures.append("Auth confirmation URL must not use localhost")
		var query_index := confirmation_url.find("?")
		var path_index := confirmation_url.find("/v1/auth/confirmed")
		if path_index < 0 or (query_index >= 0 and path_index > query_index):
			failures.append("Auth confirmation path must be inserted before gateway query routing")

	_assert_source_contains(
		"res://network/supabase_auth_client.gd",
		["redirect_to=", "resend_signup_confirmation", '_auth_endpoint("signup", redirect_url)'],
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
		"res://backend/rivet-control/src/server-full-online.ts",
		["/v1/auth/confirmed", "authConfirmationResponse"],
		failures
	)
	_assert_source_contains(
		"res://backend/supabase/email_templates/confirmation.html",
		["{{ .ConfirmationURL }}", "E-POSTAYI DOĞRULA"],
		failures
	)
	_assert_source_contains(
		"res://tools/deploy_supabase_staging.py",
		["mailer_templates_confirmation_content", "uri_allow_list", "localhost_removed"],
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
