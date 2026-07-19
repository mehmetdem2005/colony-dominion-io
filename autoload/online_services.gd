extends Node

signal configuration_loaded(configured: bool, missing: PackedStringArray)
signal regions_changed
signal matchmaking_status_changed(status: Dictionary)
signal legal_sync_completed(succeeded: bool, message: String)

var config: BackendRuntimeConfig
var auth: SupabaseAuthClient
var data: SupabaseDataClient
var region_probe: RegionProbeService
var matchmaking: RivetMatchmakingClient
var legal_store := LegalAcceptanceStore.new()
var _control_http: HttpJsonClient
var _probe_timer: Timer
var _matchmaking_cancelled: bool = false
var _catalog_refresh_in_progress: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	config = BackendRuntimeConfig.load_current()
	legal_store.load_all()

	auth = SupabaseAuthClient.new()
	auth.name = "SupabaseAuth"
	add_child(auth)
	auth.configure(
		config.supabase_url, config.supabase_publishable_key, config.persist_refresh_token
	)
	auth.session_changed.connect(_on_auth_session_changed)

	data = SupabaseDataClient.new()
	data.name = "SupabaseData"
	add_child(data)
	data.configure(config.supabase_url, config.supabase_publishable_key, auth)

	_control_http = HttpJsonClient.new()
	_control_http.name = "RivetDirectoryHTTP"
	_control_http.timeout_seconds = config.region_probe_timeout_seconds
	add_child(_control_http)

	region_probe = RegionProbeService.new()
	region_probe.name = "RegionProbe"
	add_child(region_probe)
	region_probe.configure(config.regions, config.region_probe_timeout_seconds)
	region_probe.region_updated.connect(_on_region_updated)
	region_probe.cycle_completed.connect(_on_probe_cycle_completed)

	matchmaking = RivetMatchmakingClient.new()
	matchmaking.name = "RivetMatchmaking"
	add_child(matchmaking)
	matchmaking.configure(config.rivet_control_base_url, config.build_id, config.protocol_version)
	matchmaking.queue_status_changed.connect(matchmaking_status_changed.emit)

	_probe_timer = Timer.new()
	_probe_timer.name = "RegionProbeTimer"
	_probe_timer.wait_time = config.region_probe_interval_seconds
	_probe_timer.one_shot = false
	_probe_timer.timeout.connect(refresh_region_catalog)
	add_child(_probe_timer)
	_probe_timer.start()
	call_deferred("refresh_region_catalog")
	configuration_loaded.emit(is_client_configured(), get_missing_client_settings())


func is_client_configured() -> bool:
	return auth.is_configured() and matchmaking.is_configured()


func get_missing_client_settings() -> PackedStringArray:
	return config.get_missing_client_settings()


func get_regions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for region in config.regions:
		var copy: Dictionary = region.duplicate(true)
		copy["metrics"] = region_probe.get_metrics(String(region.get("id", "")))
		result.append(copy)
	return result


func get_region(region_id: String) -> Dictionary:
	var region: Dictionary = config.get_region(region_id)
	if not region.is_empty():
		region["metrics"] = region_probe.get_metrics(region_id)
	return region


func refresh_region_catalog() -> void:
	if _catalog_refresh_in_progress:
		return
	_catalog_refresh_in_progress = true
	if matchmaking.is_configured():
		var response: Dictionary = await _control_http.request_json(
			HTTPClient.METHOD_GET,
			"%s/v1/regions" % config.rivet_control_base_url,
			PackedStringArray(["Accept: application/json", "Cache-Control: no-cache"])
		)
		if bool(response.get("ok", false)):
			var body_variant: Variant = response.get("body", {})
			if body_variant is Dictionary:
				var regions_variant: Variant = (body_variant as Dictionary).get("regions", [])
				var normalized: Array[Dictionary] = _normalize_regions(regions_variant)
				if not normalized.is_empty():
					config.regions = normalized
					region_probe.configure(config.regions, config.region_probe_timeout_seconds)
					regions_changed.emit()
	_catalog_refresh_in_progress = false
	probe_regions()


func probe_regions() -> void:
	if not is_instance_valid(region_probe):
		return
	NetworkSession.set_connection_state(
		NetworkSession.ConnectionState.PROBING, "Bölgeler ölçülüyor"
	)
	region_probe.probe_all()


func select_region(region_id: String) -> void:
	if region_id == "auto":
		NetworkSession.set_preferred_region("auto")
		var best_id: String = region_probe.get_best_region_id()
		if best_id.is_empty():
			NetworkSession.select_region("auto", "Otomatik", "AUTO", {})
		else:
			_apply_region_selection(best_id, true)
		regions_changed.emit()
		_sync_preferences_deferred()
		return
	_apply_region_selection(region_id, false)
	regions_changed.emit()
	_sync_preferences_deferred()


func sync_legal_acceptances() -> Dictionary:
	if not auth.has_session():
		return {"ok": false, "error": "Yasal kayıt senkronizasyonu için oturum gerekli"}
	if not legal_store.has_required_acceptances():
		return {"ok": false, "error": "Zorunlu belgeler kabul edilmedi"}
	var rows: Array[Dictionary] = legal_store.build_remote_rows(
		auth.get_user_id(), config.build_id, "tr-TR"
	)
	var result: Dictionary = await data.upsert_legal_acceptances(rows)
	var succeeded: bool = bool(result.get("ok", false))
	var message: String = (
		"Kullanıcı sözleşmeleri kaydedildi"
		if succeeded
		else String(result.get("error", "Kullanıcı sözleşmeleri kaydedilemedi"))
	)
	legal_sync_completed.emit(succeeded, message)
	return result


func sync_preferences() -> Dictionary:
	if not auth.has_session():
		return {"ok": false, "error": "Tercih senkronizasyonu için oturum gerekli"}
	var analytics_consent: bool = legal_store.is_currently_accepted("analytics_consent")
	return await (
		data
		. update_preferences(
			{
				"preferred_region": NetworkSession.preferred_region_id,
				"language": "tr",
				"analytics_consent": analytics_consent,
			}
		)
	)


func begin_matchmaking(display_name: String) -> Dictionary:
	_matchmaking_cancelled = false
	if not legal_store.has_required_acceptances():
		return {"ok": false, "error": "Zorunlu kullanıcı belgeleri henüz onaylanmadı"}
	if not auth.has_session():
		return {"ok": false, "error": "Çevrim içi oyun için giriş yapılması gerekiyor"}
	if not is_client_configured():
		return {
			"ok": false,
			"error": "Eksik yapılandırma: %s" % ", ".join(get_missing_client_settings()),
		}
	var legal_result: Dictionary = await sync_legal_acceptances()
	if not bool(legal_result.get("ok", false)):
		return {
			"ok": false,
			"error":
			(
				"Sözleşme kaydı doğrulanamadı: %s"
				% String(legal_result.get("error", "bilinmeyen hata"))
			),
		}
	await sync_preferences()
	NetworkSession.set_online()
	NetworkSession.set_connection_state(
		NetworkSession.ConnectionState.MATCHMAKING, "Uygun maç aranıyor"
	)
	var region_preference: String = NetworkSession.preferred_region_id
	var join_result: Dictionary = await matchmaking.join_queue(
		auth.get_access_token(),
		auth.get_user_id(),
		region_preference,
		NetworkSession.selected_region_id,
		display_name
	)
	if not bool(join_result.get("ok", false)):
		NetworkSession.set_connection_state(
			NetworkSession.ConnectionState.FAILED,
			String(join_result.get("error", "Eşleştirme başlatılamadı"))
		)
		return join_result
	var initial_body_variant: Variant = join_result.get("body", {})
	if initial_body_variant is Dictionary:
		var immediate: Dictionary = _consume_queue_status(initial_body_variant as Dictionary)
		if bool(immediate.get("assigned", false)):
			return {"ok": true, "assignment": immediate.get("assignment", {})}
	for _attempt in 120:
		if _matchmaking_cancelled:
			return {"ok": false, "error": "Eşleştirme iptal edildi"}
		await get_tree().create_timer(1.0, true, false, true).timeout
		var status_result: Dictionary = await matchmaking.get_queue_status(auth.get_access_token())
		if not bool(status_result.get("ok", false)):
			continue
		var body_variant: Variant = status_result.get("body", {})
		if not body_variant is Dictionary:
			continue
		var consumed: Dictionary = _consume_queue_status(body_variant as Dictionary)
		if bool(consumed.get("assigned", false)):
			return {"ok": true, "assignment": consumed.get("assignment", {})}
		if bool(consumed.get("terminal", false)):
			return {"ok": false, "error": String(consumed.get("error", "Eşleştirme durdu"))}
	NetworkSession.set_connection_state(
		NetworkSession.ConnectionState.FAILED, "Eşleştirme zaman aşımına uğradı"
	)
	return {"ok": false, "error": "Eşleştirme zaman aşımına uğradı"}


func cancel_matchmaking() -> void:
	_matchmaking_cancelled = true
	if is_instance_valid(matchmaking):
		await matchmaking.cancel_queue(auth.get_access_token())
	NetworkSession.set_connection_state(NetworkSession.ConnectionState.IDLE, "")


func _consume_queue_status(status: Dictionary) -> Dictionary:
	matchmaking_status_changed.emit(status.duplicate(true))
	var state: String = String(status.get("status", "queued"))
	if state == "assigned":
		var assignment_variant: Variant = status.get("assignment", {})
		if not assignment_variant is Dictionary:
			return {"assigned": false, "terminal": true, "error": "Atama verisi geçersiz"}
		var assignment: Dictionary = assignment_variant
		if not _is_valid_assignment(assignment):
			return {
				"assigned": false,
				"terminal": true,
				"error": "Sunucu ataması güvenlik denetiminden geçemedi",
			}
		NetworkSession.set_match_assignment(assignment)
		var region_id: String = String(assignment.get("region_id", ""))
		if not region_id.is_empty():
			_apply_region_selection(region_id, false)
		NetworkSession.set_connection_state(
			NetworkSession.ConnectionState.CONNECTING, "Oyun sunucusuna bağlanılıyor"
		)
		return {"assigned": true, "assignment": assignment}
	if state in ["failed", "cancelled", "expired"]:
		var message: String = String(status.get("message", "Eşleştirme başarısız"))
		NetworkSession.set_connection_state(NetworkSession.ConnectionState.FAILED, message)
		return {"assigned": false, "terminal": true, "error": message}
	var position: int = int(status.get("position", -1))
	var message: String = "Uygun maç aranıyor"
	if position >= 0:
		message = "Sırada: %d" % (position + 1)
	NetworkSession.set_connection_state(NetworkSession.ConnectionState.MATCHMAKING, message)
	return {"assigned": false, "terminal": false}


func _on_region_updated(_region_id: String, _metrics: Dictionary) -> void:
	regions_changed.emit()


func _on_probe_cycle_completed(best_region_id: String) -> void:
	if NetworkSession.preferred_region_id == "auto":
		if not best_region_id.is_empty():
			_apply_region_selection(best_region_id, true)
		else:
			NetworkSession.select_region("auto", "Otomatik", "AUTO", {})
	else:
		_apply_region_selection(NetworkSession.preferred_region_id, false)
	if NetworkSession.connection_state == NetworkSession.ConnectionState.PROBING:
		NetworkSession.set_connection_state(NetworkSession.ConnectionState.IDLE, "")
	regions_changed.emit()


func _on_auth_session_changed(session: Dictionary) -> void:
	if session.is_empty():
		return
	if legal_store.has_required_acceptances():
		await sync_legal_acceptances()
	await sync_preferences()


func _apply_region_selection(region_id: String, automatic: bool) -> void:
	var region: Dictionary = get_region(region_id)
	if region.is_empty():
		NetworkSession.select_region("auto", "Otomatik", "AUTO", {})
		return
	var display_name: String = String(region.get("display_name", region_id))
	if automatic:
		display_name = "Otomatik — %s" % display_name
	NetworkSession.select_region(
		region_id,
		display_name,
		String(region.get("short_name", region_id.to_upper())),
		region.get("metrics", {}) as Dictionary
	)
	if automatic:
		NetworkSession.set_preferred_region("auto")


func _sync_preferences_deferred() -> void:
	if auth.has_session():
		call_deferred("sync_preferences")


func _normalize_regions(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	var seen: Dictionary = {}
	for region_variant in value:
		if not region_variant is Dictionary:
			continue
		var region: Dictionary = region_variant
		var region_id: String = String(region.get("id", "")).strip_edges().to_lower()
		if region_id.is_empty() or seen.has(region_id):
			continue
		var probe_url: String = String(region.get("probe_url", "")).strip_edges()
		if (
			not probe_url.begins_with("https://")
			and not (OS.is_debug_build() and probe_url.begins_with("http://"))
		):
			probe_url = ""
		seen[region_id] = true
		(
			result
			. append(
				{
					"id": region_id,
					"display_name": String(region.get("display_name", region_id)).strip_edges(),
					"short_name":
					String(region.get("short_name", region_id.to_upper())).strip_edges(),
					"probe_url": probe_url,
					"enabled": bool(region.get("enabled", true)),
				}
			)
		)
	return result


func _is_valid_assignment(assignment: Dictionary) -> bool:
	var match_id: String = String(assignment.get("match_id", "")).strip_edges()
	var server_id: String = String(assignment.get("server_id", "")).strip_edges()
	var host: String = String(assignment.get("host", "")).strip_edges()
	var port: int = int(assignment.get("port", 0))
	var join_ticket: String = String(assignment.get("join_ticket", ""))
	var protocol_version: int = int(assignment.get("protocol_version", 0))
	var expires_at: int = int(assignment.get("expires_at", 0))
	return (
		not match_id.is_empty()
		and not server_id.is_empty()
		and not host.is_empty()
		and port > 0
		and port <= 65535
		and join_ticket.length() >= 16
		and join_ticket.length() <= 256
		and protocol_version == config.protocol_version
		and expires_at > Time.get_unix_time_from_system() * 1000.0
	)
