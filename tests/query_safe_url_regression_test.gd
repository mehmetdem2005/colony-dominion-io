extends SceneTree

const URL_BUILDER := preload("res://network/query_safe_url.gd")

# Covers Rivet gateway URLs whose routing credentials live in the query string.
# The Android artifact workflow uses this regression as a mandatory release gate.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: PackedStringArray = PackedStringArray()
	_assert_equal(
		URL_BUILDER.append_path("https://example.test/request", "/v1/health"),
		"https://example.test/request/v1/health",
		"plain gateway URL",
		failures
	)
	_assert_equal(
		(
			URL_BUILDER
			. append_path(
				"https://api.rivet.dev/gateway/controlApi/request?rvt-namespace=staging&rvt-token=pk_test",
				"/v1/regions"
			)
		),
		"https://api.rivet.dev/gateway/controlApi/request/v1/regions?rvt-namespace=staging&rvt-token=pk_test",
		"query-bearing gateway URL",
		failures
	)
	_assert_equal(
		URL_BUILDER.append_path("https://example.test/request/?a=1", "v1/health/ping"),
		"https://example.test/request/v1/health/ping?a=1",
		"trailing slash normalization",
		failures
	)
	_assert_equal(
		URL_BUILDER.append_path("https://example.test/request?token=public#ignored", "/v1/health"),
		"https://example.test/request/v1/health?token=public",
		"fragment removal",
		failures
	)
	if failures.is_empty():
		print("PASS query_safe_url_regression_test")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _assert_equal(
	actual: String, expected: String, label: String, failures: PackedStringArray
) -> void:
	if actual != expected:
		failures.append("%s mismatch: expected=%s actual=%s" % [label, expected, actual])
