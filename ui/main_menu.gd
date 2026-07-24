class_name ColonyMainMenu
extends Control

const MAIN_SCENE_PATH: String = "res://scenes/main_game.tscn"
const ONLINE_SCENE_PATH: String = "res://scenes/online_game.tscn"
const BUILD_ID: String = "PHASE-05.6-ART-MAIN-MENU"

var _view: ColonyMainMenuView
var _name_input: LineEdit
var _offline_button: BaseButton
var _online_button: BaseButton
var _resume_button: BaseButton
var _region_button: BaseButton
var _account_button: Button
var _legal_button: BaseButton
var _profile_button: BaseButton
var _ranking_button: BaseButton
var _clan_button: BaseButton
var _settings_button: BaseButton
var _dock_settings_button: BaseButton
var _quit_button: BaseButton
var _status_label: Label
var _region_status: Label
var _account_status: Label
var _modal_shade: ColorRect
var _region_panel: RegionSelectorPanel
var _auth_panel: AuthPanel
var _legal_panel: LegalGatePanel
var _profile_panel: OnlineProfilePanel
var _settings_panel: SettingsPanel
var _pulse_tween: Tween
var _starting: bool = false
var _matchmaking: bool = false
var _matchmaking_generation: int = 0
var _pending_online_request: bool = false


func _ready() -> void:
	print("[Colony Dominion] Build: %s" % BUILD_ID)
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioSystem.enter_menu()
	_build_menu()
	_connect_services()
	_refresh_status()
	OnlineServices.probe_regions()
	_play_entrance()
	_pulse_primary()
	call_deferred("_try_resume_previous_match")


func _build_menu() -> void:
	_view = ColonyMainMenuView.new()
	_view.name = "ArtMainMenuView"
	add_child(_view)
	_view.build()

	_name_input = _view.player_name_input
	_name_input.text = GameSession.player_name
	_offline_button = _view.offline_button
	_online_button = _view.online_button
	_resume_button = _view.resume_button
	_region_button = _view.region_button
	_account_button = _view.account_button
	_legal_button = _view.legal_button
	_profile_button = _view.profile_button
	_ranking_button = _view.ranking_button
	_clan_button = _view.clan_button
	_settings_button = _view.settings_button
	_dock_settings_button = _view.dock_settings_button
	_quit_button = _view.quit_button
	_status_label = _view.status_label
	_region_status = _view.region_status_label
	_account_status = _view.account_status_label

	_view.offline_requested.connect(_start_offline)
	_view.online_requested.connect(_request_online_play)
	_view.resume_requested.connect(_resume_online_match)
	_view.settings_requested.connect(_open_settings)
	_view.quit_requested.connect(_quit_game)
	_view.region_requested.connect(_open_region_selector)
	_view.account_requested.connect(_on_account_pressed)
	_view.legal_requested.connect(_open_legal_gate)
	_view.profile_requested.connect(_open_profile_panel)
	_view.ranking_requested.connect(_open_ranking_panel)
	_view.clan_requested.connect(_open_clan)

	_build_modals()


func _play_entrance() -> void:
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.42).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_OUT
	)


func _pulse_primary() -> void:
	if not is_instance_valid(_online_button):
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(
		_online_button, "self_modulate", Color(1.08, 1.06, 0.96, 1.0), 1.25
	).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(
		_online_button, "self_modulate", Color.WHITE, 1.25
	).set_trans(Tween.TRANS_SINE)


func _build_modals() -> void:
	_modal_shade = ColorRect.new()
	_modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_shade.color = Color(0.0, 0.0, 0.0, 0.78)
	_modal_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_shade.visible = false
	add_child(_modal_shade)

	_region_panel = RegionSelectorPanel.new()
	_region_panel.region_selected.connect(_on_region_selected)
	_region_panel.closed.connect(_on_modal_closed)
	add_child(_region_panel)

	_auth_panel = AuthPanel.new()
	_auth_panel.authenticated.connect(_on_authenticated)
	_auth_panel.closed.connect(_on_modal_closed)
	add_child(_auth_panel)

	_legal_panel = LegalGatePanel.new()
	_legal_panel.accepted.connect(_on_legal_accepted)
	_legal_panel.closed.connect(_on_modal_closed)
	add_child(_legal_panel)

	_profile_panel = OnlineProfilePanel.new()
	_profile_panel.closed.connect(_on_modal_closed)
	add_child(_profile_panel)

	_settings_panel = SettingsPanel.new()
	_settings_panel.closed.connect(_on_settings_closed)
	add_child(_settings_panel)


func _connect_services() -> void:
	OnlineServices.regions_changed.connect(_refresh_status)
	OnlineServices.matchmaking_status_changed.connect(_on_matchmaking_status)
	OnlineServices.auth.session_changed.connect(_on_session_changed)
	NetworkSession.region_changed.connect(_refresh_status.unbind(2))
	NetworkSession.metrics_changed.connect(_refresh_status.unbind(3))
	NetworkSession.connection_state_changed.connect(_on_connection_state_changed)


func _start_offline() -> void:
	if _starting or _matchmaking:
		return
	_save_player_name()
	GameSession.prepare_offline_match()
	_starting = true
	_set_buttons_enabled(false)
	_show_status("Çevrimdışı savaş alanı hazırlanıyor", false)
	AudioSystem.play_ui(&"ui_select")
	call_deferred("_change_to_offline_game")


func _request_online_play() -> void:
	if _starting:
		return
	if _matchmaking:
		_cancel_matchmaking()
		return
	_save_player_name()
	_pending_online_request = true
	if not OnlineServices.legal_store.has_required_acceptances():
		_open_legal_gate()
		return
	var missing: PackedStringArray = OnlineServices.get_missing_client_settings()
	if not missing.is_empty():
		_pending_online_request = false
		_show_status("Çevrim içi yapılandırma eksik: %s" % ", ".join(missing), true)
		return
	if not OnlineServices.auth.has_session():
		_open_auth_panel()
		return
	_begin_matchmaking()


func _try_resume_previous_match() -> void:
	await get_tree().create_timer(0.35, true, false, true).timeout
	if _starting or _matchmaking:
		return
	if GameTransport.has_persisted_reconnect_session(OnlineServices.config.build_id):
		_resume_online_match()


func _resume_online_match() -> void:
	if _starting or _matchmaking:
		return
	var build_id: String = OnlineServices.config.build_id
	var summary: Dictionary = GameTransport.get_persisted_reconnect_summary(build_id)
	if summary.is_empty():
		_refresh_status()
		_show_status("Devam eden maç oturumunun süresi doldu", true)
		return
	_starting = true
	_set_buttons_enabled(false)
	_show_status("Devam eden maça yeniden bağlanılıyor", false)
	var resume_result: Dictionary = GameTransport.resume_persisted_session(build_id)
	if not bool(resume_result.get("ok", false)):
		_start_error(String(resume_result.get("error", "Yeniden bağlantı başlatılamadı")))
		return
	var assignment_variant: Variant = resume_result.get("assignment", {})
	if not assignment_variant is Dictionary:
		_start_error("Kaydedilmiş maç ataması geçersiz")
		return
	var assignment: Dictionary = assignment_variant
	GameSession.prepare_online_match(assignment)
	var auth_result: Dictionary = await GameTransport.wait_for_authentication(12.0)
	if not bool(auth_result.get("ok", false)):
		GameTransport.clear_persisted_reconnect_session()
		GameTransport.disconnect_from_game("Yeniden bağlantı başarısız")
		_start_error(String(auth_result.get("error", "Yeniden kimlik doğrulama başarısız")))
		return
	_change_to_online_game()


func _begin_matchmaking() -> void:
	if _matchmaking:
		return
	_pending_online_request = false
	_matchmaking_generation += 1
	var generation: int = _matchmaking_generation
	_matchmaking = true
	_view.set_online_button_text("EŞLEŞTİRMEYİ İPTAL ET")
	_set_buttons_enabled(false)
	_online_button.disabled = false
	var result: Dictionary = await OnlineServices.begin_matchmaking(GameSession.player_name)
	if generation != _matchmaking_generation:
		return
	_matchmaking = false
	_view.set_online_button_text("ÇEVRİM İÇİ")
	if bool(result.get("ok", false)):
		_starting = true
		_set_buttons_enabled(false)
		var assignment_variant: Variant = result.get("assignment", {})
		if not assignment_variant is Dictionary:
			_start_error("Sunucu ataması geçersiz")
			return
		var assignment: Dictionary = assignment_variant
		GameSession.prepare_online_match(assignment)
		var connect_result: Dictionary = GameTransport.connect_to_assignment(
			assignment,
			OnlineServices.auth.get_user_id(),
			GameSession.player_name,
			OnlineServices.config.build_id
		)
		if not bool(connect_result.get("ok", false)):
			_start_error(String(connect_result.get("error", "Sunucu bağlantısı başlatılamadı")))
			return
		_show_status("Oyun sunucusuna bağlanılıyor", false)
		var auth_result: Dictionary = await GameTransport.wait_for_authentication(12.0)
		if not bool(auth_result.get("ok", false)):
			GameTransport.disconnect_from_game("Kimlik doğrulama başarısız")
			_start_error(String(auth_result.get("error", "Sunucu doğrulaması başarısız")))
			return
		_change_to_online_game()
		return
	_set_buttons_enabled(true)
	_show_status(String(result.get("error", "Eşleştirme başarısız")), true)


func _cancel_matchmaking() -> void:
	_matchmaking_generation += 1
	_matchmaking = false
	_view.set_online_button_text("ÇEVRİM İÇİ")
	_set_buttons_enabled(true)
	OnlineServices.cancel_matchmaking()
	_show_status("Eşleştirme iptal edildi", false)


func _change_to_online_game() -> void:
	if not ResourceLoader.exists(ONLINE_SCENE_PATH, "PackedScene"):
		_start_error("Çevrim içi oyun sahnesi bulunamadı")
		return
	_starting = true
	_set_buttons_enabled(false)
	var error: Error = get_tree().change_scene_to_file(ONLINE_SCENE_PATH)
	if error != OK:
		_start_error("Çevrim içi sahne geçişi başarısız: %s" % error_string(error))


func _change_to_offline_game() -> void:
	if not ResourceLoader.exists(MAIN_SCENE_PATH, "PackedScene"):
		_start_error("Ana oyun sahnesi bulunamadı")
		return
	var scene := load(MAIN_SCENE_PATH) as PackedScene
	if scene == null:
		_start_error("Ana oyun sahnesi yüklenemedi")
		return
	var error: Error = get_tree().change_scene_to_packed(scene)
	if error != OK:
		_start_error("Sahne geçişi başarısız: %s" % error_string(error))


func _open_region_selector() -> void:
	_set_modal_visible(true)
	_region_panel.open_panel()


func _open_auth_panel() -> void:
	_set_modal_visible(true)
	_auth_panel.open_panel(GameSession.player_name)


func _open_legal_gate() -> void:
	_set_modal_visible(true)
	_legal_panel.open_panel()


func _open_ranking_panel() -> void:
	_open_profile_panel()


func _open_profile_panel() -> void:
	if not OnlineServices.auth.has_session():
		_open_auth_panel()
		return
	_set_modal_visible(true)
	_profile_panel.open_panel()


func _open_clan() -> void:
	_show_status("Klan servisi henüz bu oyun sunucusuna bağlanmadı", false)
	AudioSystem.play_ui(&"ui_select")


func _open_settings() -> void:
	_set_modal_visible(true)
	_settings_panel.open_panel()


func _quit_game() -> void:
	if _starting or _matchmaking:
		return
	_save_player_name()
	get_tree().quit()


func _on_settings_closed() -> void:
	_set_modal_visible(false)
	_refresh_status()


func _on_account_pressed() -> void:
	if OnlineServices.auth.has_session():
		GameTransport.clear_persisted_reconnect_session()
		OnlineServices.auth.sign_out()
		_show_status("Oturum kapatıldı", false)
		return
	_open_auth_panel()


func _on_region_selected(_region_id: String) -> void:
	_set_modal_visible(false)
	_refresh_status()


func _on_authenticated() -> void:
	_set_modal_visible(false)
	_refresh_status()
	if _pending_online_request:
		_request_online_play()


func _on_legal_accepted() -> void:
	_set_modal_visible(false)
	_refresh_status()
	if OnlineServices.auth.has_session():
		var sync_result: Dictionary = await OnlineServices.sync_legal_acceptances()
		if not bool(sync_result.get("ok", false)):
			_show_status(
				(
					"Sözleşme kaydı senkronize edilemedi: %s"
					% String(sync_result.get("error", "bilinmeyen hata"))
				),
				true
			)
			return
	if _pending_online_request:
		_request_online_play()


func _on_modal_closed() -> void:
	_pending_online_request = false
	_set_modal_visible(false)


func _on_session_changed(_session: Dictionary) -> void:
	_refresh_status()


func _on_matchmaking_status(status: Dictionary) -> void:
	var state: String = String(status.get("status", "queued"))
	if state == "queued":
		var position: int = int(status.get("position", -1))
		var humans := maxi(int(status.get("human_players_waiting", 1)), 1)
		var target := maxi(int(status.get("target_players", 10)), humans)
		var seconds := maxi(int(status.get("bot_backfill_seconds_remaining", 0)), 0)
		var message := (
			"Eşleştirme • %d/%d insan • %d sn sonra botlarla tamamlanır"
			% [humans, target, seconds]
		)
		if position > 0:
			message += " • sıra %d" % (position + 1)
		_show_status(message, false)


func _on_connection_state_changed(_state: int, message: String) -> void:
	if not message.is_empty() and _matchmaking:
		_show_status(message, false)


func _refresh_status() -> void:
	if not is_instance_valid(_region_status):
		return
	var reconnect_summary: Dictionary = GameTransport.get_persisted_reconnect_summary(
		OnlineServices.config.build_id
	)
	var can_resume: bool = not reconnect_summary.is_empty()
	_view.set_resume_visible(can_resume)
	if can_resume:
		var region_name: String = String(reconnect_summary.get("region_name", "Sunucu"))
		_view.set_resume_button_text("MAÇA DÖN • %s" % region_name)
	var ping_text: String = (
		"-- ms" if NetworkSession.ping_ms < 0 else "%d ms" % NetworkSession.ping_ms
	)
	_region_status.text = "%s • %s" % [NetworkSession.selected_region_name, ping_text]
	if NetworkSession.ping_ms >= 0 and NetworkSession.ping_ms <= 70:
		_region_status.add_theme_color_override("font_color", Color(0.45, 1.0, 0.54, 1.0))
	elif NetworkSession.ping_ms >= 0 and NetworkSession.ping_ms <= 140:
		_region_status.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32, 1.0))
	else:
		_region_status.add_theme_color_override("font_color", Color(0.90, 0.72, 0.42, 1.0))
	if OnlineServices.auth.has_session():
		_view.set_account_button_text("ÇIKIŞ")
		var user_id: String = OnlineServices.auth.get_user_id()
		_account_status.text = "Hesap bağlı • %s" % user_id.left(8)
	else:
		_view.set_account_button_text("GİRİŞ")
		_account_status.text = "Hesap bağlı değil"
	if not _starting and not _matchmaking:
		var missing: PackedStringArray = OnlineServices.get_missing_client_settings()
		if missing.is_empty():
			_show_status("Çevrimdışı hazır • Çevrim içi servisler hazır", false)
		else:
			_show_status("Çevrimdışı hazır • Online için %s gerekli" % ", ".join(missing), false)


func _set_modal_visible(value: bool) -> void:
	_modal_shade.visible = value
	_view.visible = not value
	_set_buttons_enabled(not value and not _starting and not _matchmaking)


func _set_buttons_enabled(enabled: bool) -> void:
	for button in _view.all_interactive_buttons():
		if is_instance_valid(button):
			button.disabled = not enabled
	if _matchmaking and is_instance_valid(_online_button):
		_online_button.disabled = false
	if is_instance_valid(_name_input):
		_name_input.editable = enabled


func _save_player_name() -> void:
	GameSession.set_player_name(_name_input.text)


func _show_status(message: String, is_error: bool) -> void:
	_status_label.text = message
	_status_label.add_theme_color_override(
		"font_color", Color(1.0, 0.38, 0.30, 1.0) if is_error else Color(0.86, 0.82, 0.66, 1.0)
	)


func _start_error(message: String) -> void:
	_starting = false
	_set_buttons_enabled(true)
	_show_status(message, true)
	push_error(message)
