class_name SupabaseDataClient
extends Node

var _base_url: String = ""
var _publishable_key: String = ""
var _auth: SupabaseAuthClient
var _http: HttpJsonClient


func _ready() -> void:
	_http = HttpJsonClient.new()
	_http.name = "DataHTTP"
	add_child(_http)


func configure(base_url: String, publishable_key: String, auth_client: SupabaseAuthClient) -> void:
	_base_url = base_url.trim_suffix("/")
	_publishable_key = publishable_key.strip_edges()
	_auth = auth_client


func is_ready_for_user_data() -> bool:
	return (
		_base_url.begins_with("https://")
		and not _publishable_key.is_empty()
		and is_instance_valid(_auth)
		and _auth.has_session()
	)


func fetch_profile() -> Dictionary:
	if not is_ready_for_user_data():
		return {"ok": false, "error": "Kullanıcı veri oturumu hazır değil"}
	var user_id: String = _auth.get_user_id()
	var response: Dictionary = await (
		_http
		. request_json(
			HTTPClient.METHOD_GET,
			(
				"%s/rest/v1/profiles?user_id=eq.%s&select=user_id,display_name,avatar_id"
				% [
					_base_url,
					user_id.uri_encode(),
				]
			),
			_user_headers()
		)
	)
	return _normalize_response(response)


func update_preferences(preferences: Dictionary) -> Dictionary:
	if not is_ready_for_user_data():
		return {"ok": false, "error": "Kullanıcı veri oturumu hazır değil"}
	var body: Dictionary = preferences.duplicate(true)
	body["user_id"] = _auth.get_user_id()
	var headers: PackedStringArray = _user_headers()
	headers.append("Prefer: resolution=merge-duplicates,return=representation")
	var response: Dictionary = await _http.request_json(
		HTTPClient.METHOD_POST,
		"%s/rest/v1/player_preferences?on_conflict=user_id" % _base_url,
		headers,
		body
	)
	return _normalize_response(response)


func upsert_legal_acceptances(rows: Array[Dictionary]) -> Dictionary:
	if not is_ready_for_user_data():
		return {"ok": false, "error": "Kullanıcı veri oturumu hazır değil"}
	if rows.is_empty():
		return {"ok": true, "body": []}
	var headers: PackedStringArray = _user_headers()
	headers.append("Prefer: resolution=merge-duplicates,return=minimal")
	var response: Dictionary = await _http.request_json(
		HTTPClient.METHOD_POST,
		(
			(
				"%s/rest/v1/legal_acceptances?on_conflict="
				+ "user_id,document_type,document_version,locale"
			)
			% _base_url
		),
		headers,
		rows
	)
	return _normalize_response(response)


func fetch_current_rating() -> Dictionary:
	if not is_ready_for_user_data():
		return {"ok": false, "error": "Kullanıcı veri oturumu hazır değil"}
	var response: Dictionary = await (
		_http
		. request_json(
			HTTPClient.METHOD_GET,
			(
				"%s/rest/v1/player_ratings?user_id=eq.%s&select=rating,peak_rating,wins,losses,matches_played,provisional_matches,updated_at&order=updated_at.desc&limit=1"
				% [_base_url, _auth.get_user_id().uri_encode()]
			),
			_user_headers()
		)
	)
	return _normalize_response(response)


func fetch_rating_history(limit: int = 10) -> Dictionary:
	if not is_ready_for_user_data():
		return {"ok": false, "error": "Kullanıcı veri oturumu hazır değil"}
	var response: Dictionary = await (
		_http
		. request_json(
			HTTPClient.METHOD_GET,
			(
				"%s/rest/v1/rating_history?user_id=eq.%s&select=rating_before,rating_after,rating_delta,placement,created_at&order=created_at.desc&limit=%d"
				% [_base_url, _auth.get_user_id().uri_encode(), clampi(limit, 1, 30)]
			),
			_user_headers()
		)
	)
	return _normalize_response(response)


func fetch_leaderboard(limit: int = 20) -> Dictionary:
	if not is_ready_for_user_data():
		return {"ok": false, "error": "Kullanıcı veri oturumu hazır değil"}
	var response: Dictionary = await _http.request_json(
		HTTPClient.METHOD_POST,
		"%s/rest/v1/rpc/get_season_leaderboard" % _base_url,
		_user_headers(),
		{"p_limit": clampi(limit, 1, 100)}
	)
	return _normalize_response(response)


func _user_headers() -> PackedStringArray:
	return PackedStringArray(
		[
			"apikey: %s" % _publishable_key,
			"Authorization: Bearer %s" % _auth.get_access_token(),
			"Accept: application/json",
		]
	)


func _normalize_response(response: Dictionary) -> Dictionary:
	if bool(response.get("ok", false)):
		return {"ok": true, "body": response.get("body", null)}
	var body_variant: Variant = response.get("body", {})
	if body_variant is Dictionary:
		var body: Dictionary = body_variant
		for key in ["message", "details", "hint", "error"]:
			if body.has(key) and not String(body[key]).is_empty():
				return {"ok": false, "error": String(body[key])}
	return {"ok": false, "error": String(response.get("error", "Veri isteği başarısız"))}
