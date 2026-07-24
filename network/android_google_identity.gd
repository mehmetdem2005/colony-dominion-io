class_name AndroidGoogleIdentity
extends Node

const PLUGIN_NAME: String = "ColonyGoogleIdentity"
const STATE_IDLE: int = 0
const STATE_PENDING: int = 1
const STATE_SUCCESS: int = 2
const STATE_CANCELLED: int = 3
const STATE_UNAVAILABLE: int = 4
const STATE_ERROR: int = 5
const SIGN_IN_TIMEOUT_SECONDS: float = 120.0

var _cancelled: bool = false
var _plugin: Object


func is_supported() -> bool:
	return OS.get_name() == "Android" and Engine.has_singleton(PLUGIN_NAME)


func sign_in(auth_client: SupabaseAuthClient, web_client_id: String) -> Dictionary:
	_cancelled = false
	if OS.get_name() != "Android":
		return _native_error("Yerel Google girişi yalnızca Android'de kullanılabilir")
	# The native plugin singleton can finish registering a fraction of a second
	# after the panel opens, so the very first tap used to miss it and show the
	# "module not found" error while the second tap worked. Give it a brief
	# window to appear before giving up.
	var resolve_attempts: int = 0
	while not _resolve_plugin() and resolve_attempts < 8 and not _cancelled:
		resolve_attempts += 1
		await get_tree().create_timer(0.12, true, false, true).timeout
	if not _resolve_plugin():
		return _native_error("Android Google kimlik modülü APK içinde bulunamadı")
	if web_client_id.strip_edges().is_empty():
		return _native_error("Google Web Client ID yapılandırılmadı")
	if not is_instance_valid(auth_client):
		return _native_error("Kimlik servisi hazır değil")

	_plugin.call("resetSignIn")
	if not bool(_plugin.call("startNativeSignIn", web_client_id.strip_edges())):
		return _native_error("Android hesap seçicisi başlatılamadı")

	var deadline_msec := Time.get_ticks_msec() + roundi(SIGN_IN_TIMEOUT_SECONDS * 1000.0)
	while not _cancelled and Time.get_ticks_msec() < deadline_msec:
		var state := int(_plugin.call("getSignInState"))
		if state == STATE_SUCCESS:
			return await _exchange_native_credential(auth_client)
		if state == STATE_CANCELLED:
			_plugin.call("resetSignIn")
			return _cancelled_result()
		if state in [STATE_UNAVAILABLE, STATE_ERROR]:
			var native_error := String(_plugin.call("getSignInError")).strip_edges()
			_plugin.call("resetSignIn")
			return _native_error(_localize_native_error(native_error))
		await get_tree().create_timer(0.1, true, false, true).timeout

	if is_instance_valid(_plugin):
		_plugin.call("cancelNativeSignIn")
		_plugin.call("resetSignIn")
	if _cancelled:
		return _cancelled_result()
	return _native_error("Android Google hesap seçicisi zaman aşımına uğradı")


func cancel() -> void:
	_cancelled = true
	if _resolve_plugin():
		_plugin.call("cancelNativeSignIn")


func _exchange_native_credential(auth_client: SupabaseAuthClient) -> Dictionary:
	var id_token := String(_plugin.call("consumeIdToken"))
	var raw_nonce := String(_plugin.call("consumeRawNonce"))
	_plugin.call("resetSignIn")
	if id_token.is_empty() or raw_nonce.is_empty():
		id_token = ""
		raw_nonce = ""
		return _native_error("Android Google kimlik yanıtı boş döndü")
	var result: Dictionary = await auth_client.sign_in_google_id_token(id_token, raw_nonce)
	id_token = ""
	raw_nonce = ""
	return result


func _resolve_plugin() -> bool:
	if is_instance_valid(_plugin):
		return true
	if not Engine.has_singleton(PLUGIN_NAME):
		return false
	_plugin = Engine.get_singleton(PLUGIN_NAME)
	return (
		is_instance_valid(_plugin)
		and _plugin.has_method("startNativeSignIn")
		and _plugin.has_method("getSignInState")
		and _plugin.has_method("consumeIdToken")
		and _plugin.has_method("consumeRawNonce")
	)


func _native_error(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _cancelled_result() -> Dictionary:
	return {"ok": false, "error": "Google girişi iptal edildi"}


func _localize_native_error(code: String) -> String:
	match code:
		"user_cancelled", "GetCredentialCancellationException":
			return "Google girişi iptal edildi"
		"GetCredentialProviderConfigurationException":
			return "Telefonda Google hesap sağlayıcısı hazır değil"
		"NoCredentialException", "GetCredentialUnsupportedException":
			return "Telefonda kullanılabilir Google hesabı bulunamadı"
		"invalid_google_id_token", "unexpected_credential_type":
			return "Google hesap yanıtı doğrulanamadı"
		_:
			return "Android Google girişi kullanılamadı" if code.is_empty() else code
