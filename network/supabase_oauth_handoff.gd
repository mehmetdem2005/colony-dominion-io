class_name SupabaseOAuthHandoff
extends Node

const HANDOFF_PATH: String = "/functions/v1/oauth-google-handoff"
const POLL_TIMEOUT_SECONDS: float = 180.0
const DEFAULT_POLL_INTERVAL_SECONDS: float = 1.0

var _base_url: String = ""
var _publishable_key: String = ""
var _http: HttpJsonClient
var _cancelled: bool = false
var _active_request_id: String = ""
var _active_secret: String = ""


func _ready() -> void:
	_http = HttpJsonClient.new()
	_http.name = "OAuthHandoffHTTP"
	_http.timeout_seconds = 15.0
	add_child(_http)


func configure(base_url: String, publishable_key: String) -> void:
	_base_url = base_url.strip_edges().trim_suffix("/")
	_publishable_key = publishable_key.strip_edges()


func is_configured() -> bool:
	return _base_url.begins_with("https://") and not _publishable_key.is_empty()


func sign_in_google(auth_client: SupabaseAuthClient) -> Dictionary:
	if not is_configured() or not is_instance_valid(auth_client):
		return {"ok": false, "error": "Google giriş servisi yapılandırılmadı"}
	if not _active_request_id.is_empty():
		return {"ok": false, "error": "Google giriş işlemi zaten devam ediyor"}

	_cancelled = false
	_active_request_id = _uuid_v4()
	_active_secret = _random_hex(32)
	if _active_request_id.is_empty() or _active_secret.is_empty():
		_clear_active()
		return {"ok": false, "error": "Güvenli Google oturumu başlatılamadı"}

	var begin_response: Dictionary = await (
		_http
		. request_json(
			HTTPClient.METHOD_POST,
			_endpoint("/begin"),
			_base_headers(),
			{
				"request_id": _active_request_id,
				"secret_hash": _sha256_hex(_active_secret),
			}
		)
	)
	if not bool(begin_response.get("ok", false)):
		var begin_error := _extract_error(begin_response, "Google giriş servisine ulaşılamadı")
		_clear_active()
		return {"ok": false, "error": begin_error}
	var begin_body_variant: Variant = begin_response.get("body", {})
	if not begin_body_variant is Dictionary:
		_clear_active()
		return {"ok": false, "error": "Google giriş yanıtı geçersiz"}
	var begin_body: Dictionary = begin_body_variant
	var authorize_url := String(begin_body.get("authorize_url", "")).strip_edges()
	if not authorize_url.begins_with("https://"):
		_clear_active()
		return {"ok": false, "error": "Google giriş adresi güvenlik denetiminden geçemedi"}
	var poll_interval := clampf(float(begin_body.get("poll_interval_ms", 1000)) / 1000.0, 0.75, 3.0)
	var open_error: Error = OS.shell_open(authorize_url)
	if open_error != OK:
		await _cancel_remote()
		_clear_active()
		return {"ok": false, "error": "Google giriş sayfası açılamadı"}

	var deadline_msec := Time.get_ticks_msec() + roundi(POLL_TIMEOUT_SECONDS * 1000.0)
	while not _cancelled and Time.get_ticks_msec() < deadline_msec:
		await get_tree().create_timer(poll_interval, true, false, true).timeout
		if _cancelled:
			break
		var poll_response: Dictionary = await _http.request_json(
			HTTPClient.METHOD_GET,
			_endpoint("/poll/%s" % _active_request_id.uri_encode()),
			_poll_headers()
		)
		var status := int(poll_response.get("status", 0))
		if bool(poll_response.get("ok", false)):
			var poll_body_variant: Variant = poll_response.get("body", {})
			if not poll_body_variant is Dictionary:
				continue
			var poll_body: Dictionary = poll_body_variant
			if not bool(poll_body.get("ready", false)):
				continue
			var refresh_token := String(poll_body.get("refresh_token", ""))
			if refresh_token.length() < 16:
				_clear_active()
				return {"ok": false, "error": "Google oturum anahtarı geçersiz"}
			_clear_active()
			return await auth_client.sign_in_refresh_token(refresh_token)
		if status in [400, 401, 403, 404, 410]:
			var poll_error := _extract_error(poll_response, "Google girişi tamamlanamadı")
			_clear_active()
			return {"ok": false, "error": poll_error}

	await _cancel_remote()
	var cancelled := _cancelled
	_clear_active()
	return {
		"ok": false,
		"error": "Google girişi iptal edildi" if cancelled else "Google giriş süresi doldu",
	}


func cancel() -> void:
	_cancelled = true


func _cancel_remote() -> void:
	if _active_request_id.is_empty() or _active_secret.is_empty() or not is_configured():
		return
	await _http.request_json(
		HTTPClient.METHOD_DELETE,
		_endpoint("/cancel/%s" % _active_request_id.uri_encode()),
		_poll_headers()
	)


func _endpoint(path: String) -> String:
	return "%s%s/%s" % [_base_url, HANDOFF_PATH, path.trim_prefix("/")]


func _base_headers() -> PackedStringArray:
	return PackedStringArray(
		[
			"apikey: %s" % _publishable_key,
			"Accept: application/json",
			"Cache-Control: no-store",
		]
	)


func _poll_headers() -> PackedStringArray:
	var headers := _base_headers()
	headers.append("x-colony-oauth-secret: %s" % _active_secret)
	return headers


func _clear_active() -> void:
	_active_request_id = ""
	_active_secret = ""
	_cancelled = false


func _extract_error(response: Dictionary, fallback: String) -> String:
	var body_variant: Variant = response.get("body", {})
	if body_variant is Dictionary:
		var body: Dictionary = body_variant
		var message := String(body.get("error", "")).strip_edges()
		if not message.is_empty():
			return _localize_error(message)
	var transport_error := String(response.get("error", "")).strip_edges()
	return transport_error if not transport_error.is_empty() else fallback


func _localize_error(message: String) -> String:
	match message:
		"handoff_expired", "handoff_expired_or_completed":
			return "Google giriş süresi doldu. Yeniden dene."
		"handoff_store_unavailable", "oauth_handoff_unavailable":
			return "Google giriş servisi geçici olarak kullanılamıyor."
		"handoff_secret_mismatch", "invalid_handoff_secret":
			return "Google giriş güvenlik doğrulaması başarısız oldu."
		_:
			return message


func _sha256_hex(value: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(value.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func _random_hex(byte_count: int) -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(byte_count)
	return bytes.hex_encode() if bytes.size() == byte_count else ""


func _uuid_v4() -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(16)
	if bytes.size() != 16:
		return ""
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex := bytes.hex_encode()
	return (
		"%s-%s-%s-%s-%s"
		% [
			hex.substr(0, 8),
			hex.substr(8, 4),
			hex.substr(12, 4),
			hex.substr(16, 4),
			hex.substr(20, 12),
		]
	)
