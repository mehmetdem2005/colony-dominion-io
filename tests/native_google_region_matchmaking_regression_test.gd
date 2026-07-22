extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := PackedStringArray()
	_assert_contains(
		"res://network/http_json_client.gd",
		["_active_requests", "_idle_requests", "_acquire_request", "_transport_error"],
		failures
	)
	_assert_forbidden("res://network/http_json_client.gd", ["request_busy", "var _busy"], failures)

	_assert_contains(
		"res://network/android_google_identity.gd",
		[
			"ColonyGoogleIdentity",
			"startNativeSignIn",
			"consumeIdToken",
			"consumeRawNonce",
			"sign_in_google_id_token",
		],
		failures
	)
	_assert_forbidden("res://network/android_google_identity.gd", ["fallback_allowed"], failures)
	_assert_contains(
		"res://android_plugins/colony_google_identity/src/main/java/io/colonydominion/identity/ColonyGoogleIdentity.java",
		[
			"CredentialManager",
			"GetSignInWithGoogleOption",
			"GoogleIdTokenCredential",
			"SecureRandom",
			"sha256Hex",
		],
		failures
	)
	_assert_forbidden(
		"res://android_plugins/colony_google_identity/src/main/java/io/colonydominion/identity/ColonyGoogleIdentity.java",
		["CustomTabsIntent", "openInAppBrowser", "launchUrl"],
		failures
	)
	_assert_contains(
		"res://network/supabase_auth_client.gd",
		["sign_in_google_id_token", "grant_type=id_token", '"nonce": cleaned_nonce'],
		failures
	)
	_assert_contains(
		"res://autoload/online_services.gd",
		["return await android_identity.sign_in", "Never", "timeout_seconds = 15.0"],
		failures
	)
	_assert_contains(
		"res://network/supabase_oauth_handoff.gd",
		['OS.get_name() == "Android"', "yalnızca oyun içi hesap seçici"],
		failures
	)
	_assert_forbidden(
		"res://network/supabase_oauth_handoff.gd", ["Custom Tab", "openInAppBrowser"], failures
	)

	_assert_contains(
		"res://backend/rivet-control/src/rivet-native-allocator.ts",
		[
			"Client<typeof runtimeRegistry>",
			"options.region = region.providerRegion",
			"gameServer.create",
		],
		failures
	)
	_assert_forbidden(
		"res://backend/rivet-control/src/rivet-native-allocator.ts",
		["options.createInRegion", "createInRegion?: string"],
		failures
	)
	_assert_contains(
		"res://backend/rivet-control/src/region-probe-gateway.ts",
		["createWithInput", "createInRegion: providerRegion", "RIVET_REGION_PROBE_READY"],
		failures
	)
	_assert_contains(
		"res://backend/rivet-control/src/region-probe-actor.ts",
		['scope: "region-probe"', "provider_region", 'endsWith("/v1/ping")'],
		failures
	)
	_assert_contains(
		"res://network/region_probe_service.gd",
		['String(body.get("scope", "")) == "region-probe"', "verified_target"],
		failures
	)

	_assert_contains(
		"res://export_presets.cfg",
		[
			"gradle_build/use_gradle_build=true",
			"plugins/ColonyGoogleIdentity=true",
			'version/name="0.5.6"',
		],
		failures
	)
	_assert_forbidden("res://export_presets.cfg", ["AndroidInApp", "ColonyCustomTabs"], failures)
	_assert_contains(
		"res://.github/workflows/deploy-rivet-control-staging.yml",
		[
			"--min-scale 1",
			"--max-concurrent-actors 8",
			"CONTROL_PROVIDER_REGION",
			"RIVET_REGION_PROBE_READY",
		],
		failures
	)
	_assert_contains(
		"res://.github/workflows/build-apk.yml",
		["ANDROID_KEYSTORE_BASE64 is required", "configure_android_ci.gd"],
		failures
	)
	_assert_contains(
		"res://tools/prepare_android_native_build.sh", ["android/build/.gdignore"], failures
	)
	if FileAccess.file_exists("res://.github/workflows/deploy-rivet-control-staging-v2.yml"):
		failures.append("Obsolete cold Rivet V2 deployment workflow still exists")
	_assert_forbidden("res://tools/configure_android_ci.gd", ["settings.save()"], failures)

	if failures.is_empty():
		print("PASS native_google_region_matchmaking_regression_test")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _assert_contains(path: String, markers: Array[String], failures: PackedStringArray) -> void:
	var source := FileAccess.get_file_as_string(path)
	if source.is_empty():
		failures.append("Required source file is missing: %s" % path)
		return
	for marker in markers:
		if not source.contains(marker):
			failures.append("%s is missing marker: %s" % [path, marker])


func _assert_forbidden(path: String, markers: Array[String], failures: PackedStringArray) -> void:
	var source := FileAccess.get_file_as_string(path)
	for marker in markers:
		if source.contains(marker):
			failures.append("%s contains forbidden marker: %s" % [path, marker])
