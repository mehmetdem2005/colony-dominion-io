class_name ColonyMainMenu
extends Control

const MAIN_SCENE_PATH: String = "res://scenes/main_game.tscn"
const ONLINE_SCENE_PATH: String = "res://scenes/online_game.tscn"
const BUILD_ID: String = "PHASE-05.3-ONLINE-PRODUCTION-COMPLETION"

var _name_input: LineEdit
var _offline_button: Button
var _online_button: Button
var _resume_button: Button
var _region_button: Button
var _account_button: Button
var _legal_button: Button
var _profile_button: Button
var _status_label: Label
var _region_status: Label
var _account_status: Label
var _modal_shade: ColorRect
var _region_panel: RegionSelectorPanel
var _auth_panel: AuthPanel
var _legal_panel: LegalGatePanel
var _profile_panel: OnlineProfilePanel
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
	call_deferred("_try_resume_previous_match")


func _build_menu() -> void:
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = load("res://assets/ground/ground_menu_1280x720.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.055, 0.035, 0.012, 0.50)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var nest := TextureRect.new()
	nest.texture = load("res://assets/structures/nest_blue.png")
	nest.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	nest.position = Vector2(56.0, -226.0)
	nest.size = Vector2(450.0, 450.0)
	nest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	nest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	nest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(nest)

	var commander := TextureRect.new()
	commander.texture = load("res://assets/units/commander.png")
	commander.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	commander.position = Vector2(-416.0, -180.0)
	commander.size = Vector2(320.0, 370.0)
	commander.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	commander.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	commander.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(commander)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-370.0, -350.0)
	panel.size = Vector2(740.0, 700.0)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "COLONY DOMINION.IO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 43)
	title.add_theme_color_override("font_color", Color("ffd447"))
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Kolonini büyüt • Bölgeni seç • Rakip yuvaları yık"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 19)
	subtitle.add_theme_color_override("font_color", Color(0.92, 0.92, 0.86, 1.0))
	box.add_child(subtitle)

	_name_input = LineEdit.new()
	_name_input.text = GameSession.player_name
	_name_input.placeholder_text = "Oyuncu adı"
	_name_input.max_length = 16
	_name_input.custom_minimum_size = Vector2(440.0, 50.0)
	_name_input.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_input.add_theme_font_size_override("font_size", 20)
	box.add_child(_name_input)

	_offline_button = _make_primary_button("ÇEVRİM DIŞI OYNA", Color("d69a20"))
	_offline_button.pressed.connect(_start_offline)
	box.add_child(_offline_button)

	_online_button = _make_primary_button("ÇOK OYUNCULU OYNA", Color("4ba86a"))
	_online_button.pressed.connect(_request_online_play)
	box.add_child(_online_button)

	_resume_button = _make_primary_button("DEVAM EDEN MAÇA DÖN", Color("3c83b8"))
	_resume_button.custom_minimum_size.y = 52.0
	_resume_button.pressed.connect(_resume_online_match)
	_resume_button.visible = false
	box.add_child(_resume_button)

	var region_row := HBoxContainer.new()
	region_row.alignment = BoxContainer.ALIGNMENT_CENTER
	region_row.add_theme_constant_override("separation", 10)
	box.add_child(region_row)
	_region_button = Button.new()
	_region_button.text = "BÖLGE SEÇ"
	_region_button.custom_minimum_size = Vector2(210.0, 50.0)
	_region_button.add_theme_font_size_override("font_size", 17)
	_region_button.pressed.connect(_open_region_selector)
	region_row.add_child(_region_button)
	_region_status = Label.new()
	_region_status.custom_minimum_size = Vector2(360.0, 50.0)
	_region_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_region_status.add_theme_font_size_override("font_size", 16)
	region_row.add_child(_region_status)

	var account_row := HBoxContainer.new()
	account_row.alignment = BoxContainer.ALIGNMENT_CENTER
	account_row.add_theme_constant_override("separation", 10)
	box.add_child(account_row)
	_account_button = Button.new()
	_account_button.custom_minimum_size = Vector2(210.0, 48.0)
	_account_button.add_theme_font_size_override("font_size", 16)
	_account_button.pressed.connect(_on_account_pressed)
	account_row.add_child(_account_button)
	_account_status = Label.new()
	_account_status.custom_minimum_size = Vector2(250.0, 48.0)
	_account_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_account_status.add_theme_font_size_override("font_size", 15)
	account_row.add_child(_account_status)
	_legal_button = Button.new()
	_legal_button.text = "YASAL"
	_legal_button.custom_minimum_size = Vector2(108.0, 48.0)
	_legal_button.pressed.connect(_open_legal_gate)
	account_row.add_child(_legal_button)
	_profile_button = Button.new()
	_profile_button.text = "PROFİL"
	_profile_button.custom_minimum_size = Vector2(108.0, 48.0)
	_profile_button.pressed.connect(_open_profile_panel)
	account_row.add_child(_profile_button)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(640.0, 55.0)
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", Color(0.86, 0.82, 0.66, 1.0))
	box.add_child(_status_label)

	var version := Label.new()
	version.text = (
		"Godot 4.6.3 • Üretim online runtime • Protokol %d" % OnlineServices.config.protocol_version
	)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_font_size_override("font_size", 13)
	version.add_theme_color_override("font_color", Color(0.65, 0.67, 0.60, 1.0))
	box.add_child(version)

	_build_modals()


func _build_modals() -> void:
	_modal_shade = ColorRect.new()
	_modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_shade.color = Color(0.0, 0.0, 0.0, 0.72)
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
	_online_button.text = "EŞLEŞTİRMEYİ İPTAL ET"
	_offline_button.disabled = true
	_region_button.disabled = true
	_account_button.disabled = true
	_legal_button.disabled = true
	var result: Dictionary = await OnlineServices.begin_matchmaking(GameSession.player_name)
	if generation != _matchmaking_generation:
		return
	_matchmaking = false
	_online_button.text = "ÇOK OYUNCULU OYNA"
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
	_online_button.text = "ÇOK OYUNCULU OYNA"
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


func _open_profile_panel() -> void:
	if not OnlineServices.auth.has_session():
		_open_auth_panel()
		return
	_set_modal_visible(true)
	_profile_panel.open_panel()


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
		_show_status(
			"Eşleştirme sürüyor%s" % (" • sıra %d" % (position + 1) if position >= 0 else ""), false
		)


func _on_connection_state_changed(_state: int, message: String) -> void:
	if not message.is_empty() and _matchmaking:
		_show_status(message, false)


func _refresh_status() -> void:
	if not is_instance_valid(_region_status):
		return
	var reconnect_summary: Dictionary = GameTransport.get_persisted_reconnect_summary(
		OnlineServices.config.build_id
	)
	_resume_button.visible = not reconnect_summary.is_empty()
	if _resume_button.visible:
		var region_name: String = String(reconnect_summary.get("region_name", "Sunucu"))
		_resume_button.text = "DEVAM EDEN MAÇA DÖN • %s" % region_name
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
		_profile_button.visible = true
		_account_button.text = "ÇIKIŞ YAP"
		var user_id: String = OnlineServices.auth.get_user_id()
		_account_status.text = "Hesap bağlı • %s" % user_id.left(8)
	else:
		_profile_button.visible = false
		_account_button.text = "GİRİŞ / KAYIT"
		_account_status.text = "Hesap bağlı değil"
	if not _starting and not _matchmaking:
		var missing: PackedStringArray = OnlineServices.get_missing_client_settings()
		if missing.is_empty():
			_show_status("Çevrimdışı hazır • Çevrim içi servisler yapılandırıldı", false)
		else:
			_show_status("Çevrimdışı hazır • Online için %s gerekli" % ", ".join(missing), false)


func _set_modal_visible(value: bool) -> void:
	_modal_shade.visible = value
	_set_buttons_enabled(not value and not _starting and not _matchmaking)


func _set_buttons_enabled(enabled: bool) -> void:
	_offline_button.disabled = not enabled
	_online_button.disabled = not enabled and not _matchmaking
	_resume_button.disabled = not enabled
	_region_button.disabled = not enabled
	_account_button.disabled = not enabled
	_legal_button.disabled = not enabled
	_profile_button.disabled = not enabled
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


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.02, 0.90)
	style.border_color = Color(1.0, 0.76, 0.14, 0.92)
	style.set_border_width_all(3)
	style.set_corner_radius_all(28)
	style.content_margin_left = 36.0
	style.content_margin_right = 36.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 24.0
	return style


func _make_primary_button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(440.0, 66.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", Color(0.06, 0.05, 0.02, 1.0))
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.border_color = color.lightened(0.42)
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(17)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.15)
	pressed.content_margin_top = 4.0
	button.add_theme_stylebox_override("pressed", pressed)
	return button
