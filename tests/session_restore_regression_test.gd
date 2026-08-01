extends Node

# Runs as a scene so the autoloads exist before anything here loads.

## A refresh already under way must be joined, not repeated.
##
## Two callers reach refresh_session() on almost every launch: the restore that
## starts a frame after boot, and the player pressing a button that needs a
## session before that has come back. The HTTP client is single-flight and
## answers the second one with request_busy at once, so a stored session that
## was perfectly good got reported as "not signed in" and the Google screen
## appeared on a relaunch the player had never signed out of. Supabase also
## rotates refresh tokens, so a second request with the same token presents an
## already-consumed one and can invalidate the session outright.

const CLIENT_SCRIPT_PATH: String = "res://network/supabase_auth_client.gd"

var _failures: Array[String] = []


func _ready() -> void:
	_run_test.call_deferred()


func _run_test() -> void:
	var client_script := load(CLIENT_SCRIPT_PATH) as GDScript
	if client_script == null:
		_fail("Auth client script could not be loaded")
		return
	var client := client_script.new() as SupabaseAuthClient
	if client == null:
		_fail("Auth client did not instantiate")
		return
	get_tree().root.add_child(client)
	await get_tree().process_frame

	# A caller arriving while a refresh is in flight waits for that result
	# rather than firing a second request with the same token.
	client.set("_refresh_in_flight", true)
	client.set("_session", {"refresh_token": "a".repeat(48)})
	var joined: Array = []
	_join_refresh(client, joined)
	await get_tree().process_frame
	if not joined.is_empty():
		_failures.append("A concurrent refresh returned instead of joining the one in flight")
	else:
		var settled := {"ok": true, "body": {"marker": "shared"}}
		client.refresh_completed.emit(settled)
		await get_tree().process_frame
		if joined.is_empty():
			_failures.append("A joined refresh never received the in-flight result")
		elif not bool((joined[0] as Dictionary).get("ok", false)):
			_failures.append("A joined refresh did not receive the in-flight result")

	# With nothing in flight and no stored token there is nothing to refresh,
	# and that must be reported rather than hanging on the signal.
	client.set("_refresh_in_flight", false)
	client.set("_session", {})
	var empty: Dictionary = await client.refresh_session()
	if bool(empty.get("ok", false)):
		_failures.append("Refresh reported success with no stored token")

	client.queue_free()
	_finish()


func _join_refresh(client: SupabaseAuthClient, sink: Array) -> void:
	var result: Dictionary = await client.refresh_session()
	sink.append(result)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS session_restore_regression_test")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
