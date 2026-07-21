class_name RivetMatchmakingClient
extends Node

signal queue_status_changed(status: Dictionary)

var _base_url: String = ""
var _build_id: String = ""
var _protocol_version: int = 1
var _http: HttpJsonClient
var _queue_ticket_id: String = ""


func _ready() -> void:
	_http = HttpJsonClient.new()
	_http.name = "RivetControlHTTP"
	add_child(_http)


func configure(base_url: String, build_id: String, protocol_version: int) -> void:
	_base_url = base_url.trim_suffix("/")
	_build_id = build_id
	_protocol_version = maxi(protocol_version, 1)


func is_configured() -> bool:
	return (
		_base_url.begins_with("https://")
		or (OS.is_debug_build() and _base_url.begins_with("http://"))
	)


# The RivetKit Engine gateway base URL may carry a routing query string
# (rvt-namespace, rvt-token, ...). Insert the REST path before that query so the
# composed request URL stays valid.
func _endpoint_url(path_suffix: String) -> String:
	var query_index: int = _base_url.find("?")
	if query_index < 0:
		return _base_url + path_suffix
	return _base_url.substr(0, query_index) + path_suffix + _base_url.substr(query_index)


func join_queue(
	access_token: String,
	player_id: String,
	region_preference: String,
	selected_region_id: String,
	display_name: String
) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "Rivet kontrol adresi yapılandırılmadı"}
	var response: Dictionary = await (
		_http
		. request_json(
			HTTPClient.METHOD_POST,
			_endpoint_url("/v1/matchmaking/join"),
			_auth_headers(access_token),
			{
				"player_id": player_id,
				"display_name": display_name,
				"region_preference": region_preference,
				"selected_region_id": selected_region_id,
				"build_id": _build_id,
				"protocol_version": _protocol_version,
			}
		)
	)
	if not bool(response.get("ok", false)):
		return {"ok": false, "error": _extract_error(response)}
	var body_variant: Variant = response.get("body", {})
	if not body_variant is Dictionary:
		return {"ok": false, "error": "Eşleştirme yanıtı geçersiz"}
	var body: Dictionary = body_variant
	_queue_ticket_id = String(body.get("queue_ticket_id", ""))
	queue_status_changed.emit(body.duplicate(true))
	return {"ok": true, "body": body}


func get_queue_status(access_token: String) -> Dictionary:
	if _queue_ticket_id.is_empty():
		return {"ok": false, "error": "Aktif eşleştirme bileti yok"}
	var response: Dictionary = await _http.request_json(
		HTTPClient.METHOD_GET,
		_endpoint_url("/v1/matchmaking/status/%s" % _queue_ticket_id.uri_encode()),
		_auth_headers(access_token)
	)
	if not bool(response.get("ok", false)):
		return {"ok": false, "error": _extract_error(response)}
	var body_variant: Variant = response.get("body", {})
	if body_variant is Dictionary:
		queue_status_changed.emit((body_variant as Dictionary).duplicate(true))
	return {"ok": true, "body": body_variant}


func cancel_queue(access_token: String) -> void:
	if _queue_ticket_id.is_empty() or not is_configured():
		_queue_ticket_id = ""
		return
	await _http.request_json(
		HTTPClient.METHOD_DELETE,
		_endpoint_url("/v1/matchmaking/%s" % _queue_ticket_id.uri_encode()),
		_auth_headers(access_token)
	)
	_queue_ticket_id = ""


func clear_ticket() -> void:
	_queue_ticket_id = ""


func _auth_headers(access_token: String) -> PackedStringArray:
	return PackedStringArray(
		[
			"Authorization: Bearer %s" % access_token,
			"Accept: application/json",
		]
	)


func _extract_error(response: Dictionary) -> String:
	var body_variant: Variant = response.get("body", {})
	if body_variant is Dictionary:
		var body: Dictionary = body_variant
		for key in ["message", "error", "detail"]:
			if body.has(key):
				return String(body[key])
	return String(response.get("error", "Eşleştirme isteği başarısız"))
