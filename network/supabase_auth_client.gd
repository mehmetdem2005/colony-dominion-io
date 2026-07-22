class_name SupabaseAuthClient
extends Node

signal session_changed(session: Dictionary)
signal auth_error(message: String)

const SESSION_PATH: String = "user://supabase_session.vault"
const PKCE_VERIFIER_PATTERN: String = "^[A-Za-z0-9._~-]{43,128}$"

var _base_url: String = ""
var _publishable_key: String = ""
var _persist_refresh_token: bool = false
var _http: HttpJsonClient
var _session: Dictionary = {}


func _ready() -> void:
	_http = HttpJsonClient.new()
	_http.name = "AuthHTTP"
	_http.timeout_seconds = 15.0
	add_child(_http)


func configure(base_url: String, publishable_key: String, persist_refresh_token: bool) -> void:
	_base_url = base_url.trim_suffix("/")
	_publishable_key = publishable_key.strip_edges()
	_persist_refresh_token = persist_refresh_token
	if _persist_refresh_token:
		_restore_session()


func is_configured() -> bool:
	return _base_url.begins_with("https://") and not _publishable_key.is_empty()


func has_session() -> bool:
	return not String(_session.get("access_token", "")).is_empty()


func get_session() -> Dictionary:
	return _session.duplicate(true)


func get_access_token() -> String:
	return String(_session.get("access_token", ""))


func get_user_id() -> String:
	var user_variant: Variant = _session.get("user", {})
	if not user_variant is Dictionary:
		return ""
	return String((user_variant as Dictionary).get("id", ""))


func sign_in_email(email: String, password: String) -> Dictionary:
	if not is_configured():
		return _fail("Supabase istemci ayarları eksik")
	var response: Dictionary = await _http.request_json(
		HTTPClient.METHOD_POST,
		"%s/auth/v1/token?grant_type=password" % _base_url,
		_base_headers(),
		{"email": email.strip_edges(), "password": password}
	)
	return _consume_auth_response(response)


func sign_up_email(
	email: String, password: String, display_name: String, redirect_url: String = ""
) -> Dictionary:
	if not is_configured():
		return _fail("Supabase istemci ayarları eksik")
	var response: Dictionary = await (
		_http
		. request_json(
			HTTPClient.METHOD_POST,
			_auth_endpoint("signup", redirect_url),
			_base_headers(),
			{
				"email": email.strip_edges(),
				"password": password,
				"data": {"display_name": display_name.strip_edges().left(24)},
			}
		)
	)
	if bool(response.get("ok", false)):
		var body_variant: Variant = response.get("body", {})
		if body_variant is Dictionary:
			var body: Dictionary = body_variant
			if body.has("access_token"):
				_set_session(body)
			return {"ok": true, "body": body}
	return _fail(_extract_error(response))


func resend_signup_confirmation(email: String, redirect_url: String = "") -> Dictionary:
	if not is_configured():
		return _fail("Supabase istemci ayarları eksik")
	var response: Dictionary = await _http.request_json(
		HTTPClient.METHOD_POST,
		_auth_endpoint("resend", redirect_url),
		_base_headers(),
		{"type": "signup", "email": email.strip_edges()}
	)
	if bool(response.get("ok", false)):
		return {"ok": true, "body": response.get("body", {})}
	return _fail(_extract_error(response))


func sign_in_pkce_code(auth_code: String, code_verifier: String) -> Dictionary:
	if not is_configured():
		return _fail("Supabase istemci ayarları eksik")
	var cleaned_code := auth_code.strip_edges()
	var cleaned_verifier := code_verifier.strip_edges()
	var verifier_regex := RegEx.create_from_string(PKCE_VERIFIER_PATTERN)
	if (
		cleaned_code.length() < 8
		or cleaned_code.length() > 2048
		or verifier_regex.search(cleaned_verifier) == null
	):
		cleaned_code = ""
		cleaned_verifier = ""
		return _fail("Google PKCE kodu geçersiz")
	var response: Dictionary = await _http.request_json(
		HTTPClient.METHOD_POST,
		"%s/auth/v1/token?grant_type=pkce" % _base_url,
		_base_headers(),
		{"auth_code": cleaned_code, "code_verifier": cleaned_verifier}
	)
	cleaned_code = ""
	cleaned_verifier = ""
	return _consume_auth_response(response)


func sign_in_google_id_token(id_token: String, nonce: String) -> Dictionary:
	if not is_configured():
		return _fail("Supabase istemci ayarları eksik")
	var cleaned_token := id_token.strip_edges()
	var cleaned_nonce := nonce.strip_edges()
	if (
		cleaned_token.length() < 128
		or cleaned_token.length() > 16384
		or cleaned_token.count(".") != 2
		or cleaned_nonce.length() < 16
		or cleaned_nonce.length() > 256
	):
		cleaned_token = ""
		cleaned_nonce = ""
		return _fail("Google kimlik yanıtı geçersiz")
	var response: Dictionary = await (
		_http
		. request_json(
			HTTPClient.METHOD_POST,
			"%s/auth/v1/token?grant_type=id_token" % _base_url,
			_base_headers(),
			{
				"provider": "google",
				"id_token": cleaned_token,
				"nonce": cleaned_nonce,
			}
		)
	)
	cleaned_token = ""
	cleaned_nonce = ""
	return _consume_auth_response(response)


func sign_in_refresh_token(refresh_token: String) -> Dictionary:
	if not is_configured():
		return _fail("Supabase istemci ayarları eksik")
	var cleaned_token := refresh_token.strip_edges()
	if cleaned_token.length() < 16 or cleaned_token.length() > 4096:
		return _fail("Google oturum anahtarı geçersiz")
	var response: Dictionary = await _http.request_json(
		HTTPClient.METHOD_POST,
		"%s/auth/v1/token?grant_type=refresh_token" % _base_url,
		_base_headers(),
		{"refresh_token": cleaned_token}
	)
	cleaned_token = ""
	return _consume_auth_response(response)


func refresh_session() -> Dictionary:
	var refresh_token: String = String(_session.get("refresh_token", ""))
	if refresh_token.is_empty():
		return _fail("Yenileme oturumu bulunamadı")
	return await sign_in_refresh_token(refresh_token)


func fetch_user() -> Dictionary:
	if not has_session():
		return _fail("Aktif oturum bulunamadı")
	var headers: PackedStringArray = _base_headers()
	headers.append("Authorization: Bearer %s" % get_access_token())
	var response: Dictionary = await _http.request_json(
		HTTPClient.METHOD_GET, "%s/auth/v1/user" % _base_url, headers
	)
	if bool(response.get("ok", false)):
		var body_variant: Variant = response.get("body", {})
		if body_variant is Dictionary:
			_session["user"] = body_variant
			_persist_session()
			session_changed.emit(get_session())
		return {"ok": true, "body": body_variant}
	return _fail(_extract_error(response))


func sign_out() -> void:
	if has_session() and is_configured():
		var headers: PackedStringArray = _base_headers()
		headers.append("Authorization: Bearer %s" % get_access_token())
		await _http.request_json(
			HTTPClient.METHOD_POST, "%s/auth/v1/logout" % _base_url, headers, {}
		)
	_clear_session()


func _consume_auth_response(response: Dictionary) -> Dictionary:
	if bool(response.get("ok", false)):
		var body_variant: Variant = response.get("body", {})
		if body_variant is Dictionary:
			_set_session(body_variant as Dictionary)
			return {"ok": true, "body": body_variant}
	return _fail(_extract_error(response))


func _set_session(value: Dictionary) -> void:
	_session = value.duplicate(true)
	_persist_session()
	session_changed.emit(get_session())


func _clear_session() -> void:
	_session.clear()
	SecureLocalVault.remove(SESSION_PATH)
	session_changed.emit({})


func _auth_endpoint(path: String, redirect_url: String = "") -> String:
	var endpoint := "%s/auth/v1/%s" % [_base_url, path.trim_prefix("/")]
	var redirect := redirect_url.strip_edges()
	if redirect.begins_with("https://"):
		return "%s?redirect_to=%s" % [endpoint, redirect.uri_encode()]
	return endpoint


func _base_headers() -> PackedStringArray:
	return PackedStringArray(
		[
			"apikey: %s" % _publishable_key,
			"Accept: application/json",
		]
	)


func _persist_session() -> void:
	if not _persist_refresh_token:
		return
	var refresh_token: String = String(_session.get("refresh_token", ""))
	if refresh_token.is_empty():
		return
	if not SecureLocalVault.write_json(SESSION_PATH, {"refresh_token": refresh_token}):
		push_warning("Auth refresh session could not be persisted")


func _restore_session() -> void:
	var stored: Dictionary = SecureLocalVault.read_json(SESSION_PATH)
	var refresh_token: String = String(stored.get("refresh_token", ""))
	if refresh_token.is_empty():
		return
	_session = {"refresh_token": refresh_token}
	call_deferred("_refresh_restored_session")


func _refresh_restored_session() -> void:
	await refresh_session()


func _extract_error(response: Dictionary) -> String:
	var body_variant: Variant = response.get("body", {})
	if body_variant is Dictionary:
		var body: Dictionary = body_variant
		for key in ["msg", "message", "error_description", "error"]:
			if body.has(key):
				return String(body[key])
	var error_text: String = String(response.get("error", ""))
	return error_text if not error_text.is_empty() else "Kimlik doğrulama isteği başarısız"


func _fail(message: String) -> Dictionary:
	auth_error.emit(message)
	return {"ok": false, "error": message}
