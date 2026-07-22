class_name SupabaseOAuthHandoff
extends Node

const HANDOFF_PATH: String = "/functions/v1/oauth-google-handoff"
const POLL_TIMEOUT_SECONDS: float = 300.0
const DEFAULT_POLL_INTERVAL_SECONDS: float = 1.0
const PKCE_VERIFIER_BYTE_COUNT: int = 32

var _base_url: String = ""
var _publishable_key: String = ""
var _http: HttpJsonClient
var _cancelled: bool = false
var _active_request_id: String = ""
var _active_secret: String = ""
var _active_code_verifier: String = ""
var _wake_poll: bool = false


func _notification(what: int) -> void:
	# When the player returns to the app from the sign-in browser, poll at once
	# instead of waiting for the next interval.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_wake_poll = true


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

	var preparation := _prepare_pkce_handoff()
	if not bool(preparation.get("ok", false)):
		return preparation
	var code_challenge := String(preparation.get("code_challenge", ""))
	var begin_result := await _begin_remote_handoff(code_challenge)
	code_challenge = ""
	if not bool(begin_result.get("ok", false)):
		_clear_active()
		return begin_result

	var authorize_url := String(begin_result.get("authorize_url", ""))
	var poll_interval := float(begin_result.get("poll_interval", DEFAULT_POLL_INTERVAL_SECONDS))
	var open_error: Error = OS.shell_open(authorize_url)
	if open_error != OK:
		await _cancel_remote()
		_clear_active()
		return {"ok": false, "error": "Google giriş sayfası açılamadı"}
	return await _poll_pkce_result(auth_client, poll_interval)


func cancel() -> void:
	_cancelled = true


func _prepare_pkce_handoff() -> Dictionary:
	_cancelled = false
	_active_request_id = _uuid_v4()
	_active_secret = _random_hex(32)
	_active_code_verifier = _random_base64_url(PKCE_VERIFIER_BYTE_COUNT)
	var code_challenge := _sha256_base64_url(_active_code_verifier)
	var valid := (
		not _active_request_id.is_empty()
		and not _active_secret.is_empty()
		and _active_code_verifier.length() == 43
		and code_challenge.length() == 43
	)
	if not valid:
		code_challenge = ""
		_clear_active()
		return {"ok": false, "error": "Güvenli Google PKCE oturumu başlatılamadı"}
	return {"ok": true, "code_challenge": code_challenge}


func _begin_remote_handoff(code_challenge: String) -> Dictionary:
	var begin_response: Dictionary = await (
		_http
		. request_json(
			HTTPClient.METHOD_POST,
			_endpoint("/begin"),
			_base_headers(),
			{
				"request_id": _active_request_id,
				"secret_hash": _sha256_hex(_active_secret),
				"code_challenge": code_challenge,
			}
		)
	)
	if not bool(begin_response.get("ok", false)):
		return {
			"ok": false,
			"error": _extract_error(begin_response, "Google giriş servisine ulaşılamadı"),
		}
	var body_variant: Variant = begin_response.get("body", {})
	if not body_variant is Dictionary:
		return {"ok": false, "error": "Google giriş yanıtı geçersiz"}
	var body: Dictionary = body_variant
	if String(body.get("flow_type", "")) != "pkce":
		return {"ok": false, "error": "Google giriş güvenlik protokolü geçersiz"}
	var authorize_url := String(body.get("authorize_url", "")).strip_edges()
	if not _is_safe_authorize_url(authorize_url):
		return {"ok": false, "error": "Google giriş adresi güvenlik denetiminden geçemedi"}
	return {
		"ok": true,
		"authorize_url": authorize_url,
		"poll_interval": clampf(float(body.get("poll_interval_ms", 1000)) / 1000.0, 0.75, 3.0),
	}


func _poll_pkce_result(auth_client: SupabaseAuthClient, poll_interval: float) -> Dictionary:
	var deadline_msec := Time.get_ticks_msec() + roundi(POLL_TIMEOUT_SECONDS * 1000.0)
	while not _cancelled and Time.get_ticks_msec() < deadline_msec:
		await _wait_before_poll(poll_interval)
		if _cancelled:
			break
		var poll_response: Dictionary = await _http.request_json(
			HTTPClient.METHOD_GET,
			_endpoint("/poll/%s" % _active_request_id.uri_encode()),
			_poll_headers()
		)
		var terminal_result := await _consume_poll_response(poll_response, auth_client)
		if bool(terminal_result.get("terminal", false)):
			terminal_result.erase("terminal")
			return terminal_result

	await _cancel_remote()
	var cancelled := _cancelled
	_clear_active()
	return {
		"ok": false,
		"error": "Google girişi iptal edildi" if cancelled else "Google giriş süresi doldu",
	}


func _wait_before_poll(seconds: float) -> void:
	_wake_poll = false
	var elapsed := 0.0
	while elapsed < seconds and not _wake_poll and not _cancelled:
		await get_tree().create_timer(0.2, true, false, true).timeout
		elapsed += 0.2


func _consume_poll_response(
	poll_response: Dictionary, auth_client: SupabaseAuthClient
) -> Dictionary:
	var result: Dictionary = {"terminal": false}
	var status := int(poll_response.get("status", 0))
	if not bool(poll_response.get("ok", false)):
		if status in [400, 401, 403, 404, 410]:
			var poll_error := _extract_error(poll_response, "Google girişi tamamlanamadı")
			_clear_active()
			result = {"terminal": true, "ok": false, "error": poll_error}
		return result

	var body_variant: Variant = poll_response.get("body", {})
	if not body_variant is Dictionary:
		return result
	var body: Dictionary = body_variant
	if String(body.get("flow_type", "")) != "pkce":
		_clear_active()
		result = {
			"terminal": true,
			"ok": false,
			"error": "Google giriş güvenlik protokolü değişti",
		}
	elif bool(body.get("ready", false)):
		result = await _exchange_ready_pkce_result(body, auth_client)
	return result


func _exchange_ready_pkce_result(body: Dictionary, auth_client: SupabaseAuthClient) -> Dictionary:
	var auth_code := String(body.get("auth_code", "")).strip_edges()
	var code_verifier := _active_code_verifier
	if auth_code.length() < 8 or code_verifier.length() < 43:
		auth_code = ""
		code_verifier = ""
		_clear_active()
		return {"terminal": true, "ok": false, "error": "Google PKCE yanıtı geçersiz"}
	_clear_active()
	var exchange_result := await auth_client.sign_in_pkce_code(auth_code, code_verifier)
	auth_code = ""
	code_verifier = ""
	exchange_result["terminal"] = true
	return exchange_result


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
	_active_code_verifier = ""
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
	var localized := message
	match message:
		"handoff_expired", "handoff_expired_or_completed":
			localized = "Google giriş süresi doldu. Yeniden dene."
		"handoff_store_unavailable", "oauth_handoff_unavailable":
			localized = "Google giriş servisi geçici olarak kullanılamıyor."
		"handoff_secret_mismatch", "invalid_handoff_secret":
			localized = "Google giriş güvenlik doğrulaması başarısız oldu."
		"google_oauth_cancelled":
			localized = "Google girişi iptal edildi."
		"google_oauth_unavailable":
			localized = "Google giriş servisi geçici olarak kullanılamıyor."
		"invalid_pkce_handoff_request", "unsupported_oauth_flow":
			localized = "Google PKCE güvenlik protokolü doğrulanamadı."
	return localized


func _is_safe_authorize_url(value: String) -> bool:
	if not value.begins_with("%s/auth/v1/authorize?" % _base_url):
		return false
	return (
		value.contains("provider=google")
		and value.contains("flow_type=pkce")
		and value.contains("code_challenge=")
		and value.contains("code_challenge_method=s256")
	)


func _sha256_hex(value: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(value.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func _sha256_base64_url(value: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(value.to_utf8_buffer()) != OK:
		return ""
	return _base64_url(context.finish())


func _random_hex(byte_count: int) -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(byte_count)
	return bytes.hex_encode() if bytes.size() == byte_count else ""


func _random_base64_url(byte_count: int) -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(byte_count)
	return _base64_url(bytes) if bytes.size() == byte_count else ""


func _base64_url(bytes: PackedByteArray) -> String:
	return (
		Marshalls
		. raw_to_base64(bytes)
		. replace("+", "-")
		. replace("/", "_")
		. trim_suffix("=")
		. trim_suffix("=")
	)


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
