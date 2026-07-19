class_name HttpJsonClient
extends Node

const JSON_CONTENT_TYPE: String = "Content-Type: application/json"

var timeout_seconds: float = 8.0
var _request: HTTPRequest
var _busy: bool = false


func _ready() -> void:
	_ensure_request()


func request_json(
	method: HTTPClient.Method,
	url: String,
	headers: PackedStringArray = PackedStringArray(),
	body: Variant = null
) -> Dictionary:
	if _busy:
		return _error_response("request_busy", 0)
	if not _is_allowed_url(url):
		return _error_response("invalid_url", 0)
	_ensure_request()
	_busy = true
	_request.timeout = timeout_seconds
	var request_headers: PackedStringArray = headers.duplicate()
	var body_text: String = ""
	if body != null:
		if not request_headers.has(JSON_CONTENT_TYPE):
			request_headers.append(JSON_CONTENT_TYPE)
		body_text = JSON.stringify(body)
	var start_msec: int = Time.get_ticks_msec()
	var start_error: Error = _request.request(url, request_headers, method, body_text)
	if start_error != OK:
		_busy = false
		return _error_response(error_string(start_error), 0)
	var completed: Array = await _request.request_completed
	_busy = false
	var result: int = int(completed[0])
	var response_code: int = int(completed[1])
	var response_headers: PackedStringArray = completed[2]
	var response_body: PackedByteArray = completed[3]
	var elapsed_msec: int = maxi(Time.get_ticks_msec() - start_msec, 0)
	var text: String = response_body.get_string_from_utf8()
	var parsed: Variant = null
	if not text.is_empty():
		parsed = JSON.parse_string(text)
	return {
		"ok": result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300,
		"result": result,
		"status": response_code,
		"headers": response_headers,
		"body": parsed if parsed != null else text,
		"elapsed_ms": elapsed_msec,
		"error": "" if result == HTTPRequest.RESULT_SUCCESS else "http_result_%d" % result,
	}


func _ensure_request() -> void:
	if is_instance_valid(_request):
		return
	_request = HTTPRequest.new()
	_request.name = "HTTPRequest"
	_request.accept_gzip = true
	add_child(_request)


func _is_allowed_url(url: String) -> bool:
	if url.begins_with("https://"):
		return true
	if not url.begins_with("http://"):
		return false
	return (
		OS.is_debug_build()
		or OS.has_feature("dedicated_server")
		or DisplayServer.get_name() == "headless"
	)


func _error_response(message: String, status: int) -> Dictionary:
	return {
		"ok": false,
		"result": HTTPRequest.RESULT_CANT_CONNECT,
		"status": status,
		"headers": PackedStringArray(),
		"body": null,
		"elapsed_ms": 0,
		"error": message,
	}
