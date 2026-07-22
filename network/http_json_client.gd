class_name HttpJsonClient
extends Node

const JSON_CONTENT_TYPE: String = "Content-Type: application/json"

var timeout_seconds: float = 8.0
var _request_sequence: int = 0
var _active_requests: Dictionary = {}
var _idle_requests: Array[HTTPRequest] = []


func request_json(
	method: HTTPClient.Method,
	url: String,
	headers: PackedStringArray = PackedStringArray(),
	body: Variant = null
) -> Dictionary:
	if not _is_allowed_url(url):
		return _error_response("invalid_url", 0)

	# HTTPRequest is deliberately scoped to one operation. A shared HTTPRequest
	# rejects overlapping calls with ERR_BUSY; account bootstrap, legal sync and
	# matchmaking are independent operations and are allowed to overlap.
	_request_sequence += 1
	var request_id: int = _request_sequence
	var request := _acquire_request(request_id)
	_active_requests[request_id] = request

	var request_headers: PackedStringArray = headers.duplicate()
	var body_text: String = ""
	if body != null:
		if not request_headers.has(JSON_CONTENT_TYPE):
			request_headers.append(JSON_CONTENT_TYPE)
		body_text = JSON.stringify(body)
	var start_msec: int = Time.get_ticks_msec()
	var start_error: Error = request.request(url, request_headers, method, body_text)
	if start_error != OK:
		_release_request(request_id, request)
		return _error_response(error_string(start_error), 0)
	var completed: Array = await request.request_completed
	_release_request(request_id, request)
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
		"error": "" if result == HTTPRequest.RESULT_SUCCESS else _transport_error(result),
		"error_code": "" if result == HTTPRequest.RESULT_SUCCESS else "http_result_%d" % result,
	}


func _acquire_request(request_id: int) -> HTTPRequest:
	var request: HTTPRequest
	if _idle_requests.is_empty():
		request = HTTPRequest.new()
		request.accept_gzip = true
		add_child(request)
	else:
		request = _idle_requests.pop_back()
	request.name = "HTTPRequest_%d" % request_id
	request.timeout = timeout_seconds
	return request


func _release_request(request_id: int, request: HTTPRequest) -> void:
	_active_requests.erase(request_id)
	if is_instance_valid(request) and not _idle_requests.has(request):
		# Keep completed nodes in a tiny connection pool. Sequential latency
		# samples reuse the same HTTPRequest/TLS connection while concurrent API
		# operations still receive separate nodes and cannot return ERR_BUSY.
		if _idle_requests.size() < 4:
			_idle_requests.append(request)
		else:
			request.queue_free()


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
		"error_code": message,
	}


func _transport_error(result: int) -> String:
	match result:
		HTTPRequest.RESULT_TIMEOUT:
			return "Sunucu zamanında yanıt vermedi. Bağlantını kontrol edip yeniden dene."
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Sunucuya bağlanılamadı. Kısa süre sonra yeniden dene."
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Sunucu adresi çözümlenemedi. İnternet bağlantını kontrol et."
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "Sunucuyla güvenli bağlantı kurulamadı."
		HTTPRequest.RESULT_NO_RESPONSE:
			return "Sunucudan yanıt alınamadı."
		_:
			return "Ağ isteği tamamlanamadı (kod %d)." % result
