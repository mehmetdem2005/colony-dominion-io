class_name EdgegapMatchmakingClient
extends Node

## Matchmaking against the Edgegap-backed Supabase Edge Function.
##
## Mirrors the old RivetMatchmakingClient interface so OnlineServices can swap to
## it with minimal changes. join_queue() asks the function to deploy a game
## server near the player; get_queue_status() polls until Edgegap reports the
## deployment READY and returns the DIRECT ip:port the client connects to over
## ENet/UDP.

signal queue_status_changed(status: Dictionary)

const FUNCTION_PATH: String = "/functions/v1/matchmaking"
# How long the client treats an assignment as valid. Comfortably longer than a
# match so validate_assignment never rejects a fresh server as "expired"; the
# Edgegap deployment enforces its own max duration server-side.
const ASSIGNMENT_TTL_MS: int = 3 * 60 * 60 * 1000  # 3 hours

var _base_url: String = ""
var _publishable_key: String = ""
var _build_id: String = ""
var _protocol_version: int = 1
var _http: HttpJsonClient
var _request_id: String = ""
var _join_ticket: String = ""
var _match_id: String = ""
var _server_id: String = ""
var _requested_region_id: String = "auto"


func _ready() -> void:
	_http = HttpJsonClient.new()
	_http.name = "EdgegapMatchmakingHTTP"
	# Edgegap deployment provisioning can take several seconds; give it room.
	_http.timeout_seconds = 20.0
	add_child(_http)


func configure(
	base_url: String, publishable_key: String, build_id: String, protocol_version: int
) -> void:
	_base_url = base_url.strip_edges().trim_suffix("/")
	_publishable_key = publishable_key.strip_edges()
	_build_id = build_id
	_protocol_version = maxi(protocol_version, 1)


func is_configured() -> bool:
	return _base_url.begins_with("https://") and not _publishable_key.is_empty()


func join_queue(
	access_token: String,
	player_id: String,
	region_preference: String,
	selected_region_id: String,
	display_name: String
) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "Eşleştirme servisi yapılandırılmadı"}
	var preferred_id: String = _normalize_region_id(region_preference)
	var selected_id: String = _normalize_region_id(selected_region_id)
	_requested_region_id = selected_id if selected_id != "auto" else preferred_id
	if _requested_region_id.is_empty():
		_requested_region_id = "auto"
	var response: Dictionary = await (
		_http
		. request_json(
			HTTPClient.METHOD_POST,
			_endpoint("/join"),
			_headers(access_token),
			{
				"player_id": player_id.strip_edges(),
				"display_name": display_name.strip_edges().left(24),
				"region_preference": preferred_id,
				"selected_region_id": selected_id,
			}
		)
	)
	if not bool(response.get("ok", false)):
		return {"ok": false, "error": _extract_error(response)}
	var body_variant: Variant = response.get("body", {})
	if not body_variant is Dictionary or not bool((body_variant as Dictionary).get("ok", false)):
		return {"ok": false, "error": _extract_error(response)}
	var body: Dictionary = body_variant
	_request_id = String(body.get("request_id", ""))
	_join_ticket = String(body.get("join_ticket", ""))
	_match_id = String(body.get("match_id", ""))
	_server_id = String(body.get("server_id", ""))
	if _request_id.is_empty() or _join_ticket.is_empty():
		return {"ok": false, "error": "Sunucu isteği başlatılamadı"}
	queue_status_changed.emit({"status": "deploying", "request_id": _request_id})
	return {"ok": true, "body": {"queue_ticket_id": _request_id}}


func get_queue_status(access_token: String) -> Dictionary:
	if _request_id.is_empty():
		return {"ok": false, "error": "Aktif eşleştirme isteği yok"}
	var response: Dictionary = await _http.request_json(
		HTTPClient.METHOD_GET,
		_endpoint("/status/%s" % _request_id.uri_encode()),
		_headers(access_token)
	)
	if not bool(response.get("ok", false)):
		return {"ok": false, "error": _extract_error(response)}
	var body_variant: Variant = response.get("body", {})
	if not body_variant is Dictionary:
		return {"ok": false, "error": "Eşleştirme yanıtı geçersiz"}
	var body: Dictionary = body_variant
	if not bool(body.get("ok", false)):
		# Deployment failed/terminated — surface as a terminal matchmaking failure.
		var failed := {
			"status": "failed", "message": String(body.get("error", "Sunucu hazırlanamadı"))
		}
		queue_status_changed.emit(failed)
		return {"ok": true, "body": failed}
	if not (bool(body.get("ready", false)) and body.has("assignment")):
		# Still provisioning — report as queued so OnlineServices keeps polling.
		var pending := {"status": "deploying"}
		queue_status_changed.emit(pending)
		return {"ok": true, "body": pending}
	# Ready: fold in the client-agreed identity so the assignment passes
	# NetworkProtocol.validate_assignment and the server's join handshake, and
	# shape it as OnlineServices._consume_queue_status expects.
	var assignment: Dictionary = (body.get("assignment", {}) as Dictionary).duplicate(true)
	assignment["join_ticket"] = _join_ticket
	assignment["match_id"] = _match_id
	assignment["server_id"] = _server_id
	assignment["build_id"] = _build_id
	assignment["protocol_version"] = _protocol_version
	if String(assignment.get("region_id", "")).is_empty():
		assignment["region_id"] = _requested_region_id
	if String(assignment.get("region_short_name", "")).is_empty():
		assignment["region_short_name"] = (
			"EDGE" if _requested_region_id == "auto" else _requested_region_id.to_upper().left(8)
		)
	# NetworkProtocol.validate_assignment requires the human/bot split to fill the
	# match and a future expiry. Each Edgegap /join deploys a fresh dedicated
	# server for this one player, and the server is launched with
	# HUMAN_PLAYER_COUNT=1 / BOT_COUNT=(max-1) backfill, so mirror that split here.
	# Without these the
	# assignment is rejected as "güvenlik denetiminden geçemedi".
	assignment["human_players"] = 1
	assignment["bot_players"] = maxi(NetworkProtocol.DEFAULT_MAX_PLAYERS - 1, 0)
	assignment["ranked"] = false
	assignment["expires_at"] = (int(Time.get_unix_time_from_system() * 1000.0) + ASSIGNMENT_TTL_MS)
	var assigned := {"status": "assigned", "assignment": assignment}
	queue_status_changed.emit(assigned.duplicate(true))
	return {"ok": true, "body": assigned}


func cancel_queue(access_token: String) -> void:
	if _request_id.is_empty() or not is_configured():
		_request_id = ""
		return
	await _http.request_json(
		HTTPClient.METHOD_DELETE,
		_endpoint("/cancel/%s" % _request_id.uri_encode()),
		_headers(access_token)
	)
	_request_id = ""


func clear_ticket() -> void:
	_request_id = ""
	_join_ticket = ""
	_match_id = ""
	_server_id = ""
	_requested_region_id = "auto"


func _endpoint(path: String) -> String:
	return "%s%s/%s" % [_base_url, FUNCTION_PATH, path.trim_prefix("/")]


func _headers(access_token: String) -> PackedStringArray:
	return PackedStringArray(
		[
			"apikey: %s" % _publishable_key,
			"Authorization: Bearer %s" % access_token,
			"Accept: application/json",
		]
	)


func _extract_error(response: Dictionary) -> String:
	var body_variant: Variant = response.get("body", {})
	if body_variant is Dictionary:
		var body: Dictionary = body_variant
		for key in ["error", "message", "detail"]:
			if body.has(key):
				return String(body[key])
	return String(response.get("error", "Eşleştirme isteği başarısız"))


func _normalize_region_id(value: String) -> String:
	var cleaned: String = value.strip_edges().to_lower()
	if cleaned.is_empty() or cleaned == "auto":
		return "auto"
	var valid := RegEx.new()
	if valid.compile("^[a-z0-9-]{2,32}$") != OK or valid.search(cleaned) == null:
		return "auto"
	return cleaned
