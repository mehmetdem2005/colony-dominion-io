class_name ColonyMainMenu
extends Control

## Front-end rebuilt to match the supplied reference art: a full-bleed ant-colony
## background, a crowned title banner up top, four ornate stone/gold action bars
## down the centre (play, region, settings, exit) and a four-icon plate dock in
## the bottom-right corner. Every label is intentionally blank for now — text will
## be painted in once the text texture and font are provided — so the buttons are
## pure art with tooltips and wired actions.

const ONLINE_SCENE_PATH: String = "res://scenes/online_game.tscn"
const MAIN_SCENE_PATH: String = "res://scenes/main_game.tscn"
const BUILD_ID: String = "PHASE-05.5-GOOGLE-BOT-BACKFILL"

const BG_PATH := "res://assets/ui/menu/frames/bg_colony.png"
const TITLE_PATH := "res://assets/ui/menu/frames/title_banner.png"
const BTN_PLAY_PATH := "res://assets/ui/menu/frames/btn_play.png"
const BTN_WORLD_PATH := "res://assets/ui/menu/frames/btn_world.png"
const BTN_SETTINGS_PATH := "res://assets/ui/menu/frames/btn_settings.png"
const BTN_EXIT_PATH := "res://assets/ui/menu/frames/btn_exit.png"
const DOCK_STRIP_PATH := "res://assets/ui/menu/frames/dock_strip.png"

# Normalised x-centres of the four plates baked into the dock strip art.
const DOCK_ICON_FRACTIONS: Array[float] = [0.19, 0.40, 0.60, 0.81]

var _play_button: TextureButton
var _world_button: TextureButton
var _settings_button: TextureButton
var _exit_button: TextureButton
var _center_buttons: Array[TextureButton] = []
var _dock_buttons: Array[Button] = []
var _status_label: Label
var _modal_shade: ColorRect
var _region_panel: RegionSelectorPanel
var _auth_panel: AuthPanel
var _legal_panel: LegalGatePanel
var _profile_panel: OnlineProfilePanel
var _settings_panel: SettingsPanel
var _clan_panel: MenuPlaceholderPanel
var _ranking_panel: MenuPlaceholderPanel
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


func _play_entrance() -> void:
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.5).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_OUT
	)


## A slow amber breathing glow on the primary "play" bar so the eye lands on the
## action the player wants first.
func _pulse_primary() -> void:
	if not is_instance_valid(_play_button):
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops()
	(
		_pulse_tween
		. tween_property(_play_button, "modulate", Color(1.16, 1.16, 1.16, 1.0), 1.15)
		. set_trans(Tween.TRANS_SINE)
	)
	_pulse_tween.tween_property(_play_button, "modulate", Color.WHITE, 1.15).set_trans(
		Tween.TRANS_SINE
	)


func _build_menu() -> void:
	var background := TextureRect.new()
	_anchor_norm(background, 0.0, 0.0, 1.0, 1.0)
	background.texture = load(BG_PATH)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# Gentle darkening so the light plates and (future) text stay legible over the
	# busy background art.
	var shade := ColorRect.new()
	_anchor_norm(shade, 0.0, 0.0, 1.0, 1.0)
	shade.color = Color(0.02, 0.015, 0.01, 0.28)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	# Crowned title banner (empty — title text arrives later).
	var title := TextureRect.new()
	_anchor_norm(title, 0.275, -0.04, 0.725, 0.34)
	title.texture = load(TITLE_PATH)
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# Central stack of four action bars.
	var column := VBoxContainer.new()
	_anchor_norm(column, 0.325, 0.42, 0.675, 0.94)
	column.add_theme_constant_override("separation", 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)

	_center_buttons.clear()
	_play_button = _bar_button(BTN_PLAY_PATH, "Oyna", _request_online_play)
	_world_button = _bar_button(BTN_WORLD_PATH, "Bölge Seç", _open_region_selector)
	_settings_button = _bar_button(BTN_SETTINGS_PATH, "Ayarlar", _open_settings)
	_exit_button = _bar_button(BTN_EXIT_PATH, "Çıkış", _request_exit)
	for button in _center_buttons:
		column.add_child(button)

	# Status line (matchmaking / connection feedback) tucked into the bottom-left.
	_status_label = Label.new()
	_anchor_norm(_status_label, 0.02, 0.90, 0.44, 0.99)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	ColonyUiKit.apply_label(_status_label, 15, 600, ColonyUiKit.TEXT_SECONDARY)
	_status_label.add_theme_color_override("font_outline_color", Color(0.02, 0.015, 0.01, 0.95))
	_status_label.add_theme_constant_override("outline_size", 5)
	add_child(_status_label)

	_build_dock()
	_build_modals()


func _bar_button(texture_path: String, tooltip: String, on_pressed: Callable) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = load(texture_path)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(280.0, 68.0)
	button.tooltip_text = tooltip
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(on_pressed)
	button.mouse_entered.connect(_on_control_hover.bind(button, true))
	button.mouse_exited.connect(_on_control_hover.bind(button, false))
	_center_buttons.append(button)
	return button


## Bottom-right plate dock. The strip art already carries the four emblem plates
## (trophy → ranking & statistics, shield → clan, chart → profile, gear →
## settings); we lay four transparent hit-areas over the baked plates.
func _build_dock() -> void:
	var dock := Control.new()
	dock.name = "IconDock"
	_anchor_norm(dock, 0.70, 0.85, 0.99, 0.99)
	add_child(dock)

	var strip := TextureRect.new()
	_anchor_norm(strip, 0.0, 0.0, 1.0, 1.0)
	strip.texture = load(DOCK_STRIP_PATH)
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock.add_child(strip)

	_dock_buttons.clear()
	var actions: Array[Dictionary] = [
		{"tip": "Sıralama & İstatistik", "cb": Callable(self, "_open_ranking_panel")},
		{"tip": "Klan", "cb": Callable(self, "_open_clan_panel")},
		{"tip": "Profil", "cb": Callable(self, "_open_profile_panel")},
		{"tip": "Ayarlar", "cb": Callable(self, "_open_settings")},
	]
	var half_width: float = 0.5 / float(DOCK_ICON_FRACTIONS.size())
	for index in actions.size():
		var frac: float = DOCK_ICON_FRACTIONS[index]
		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		_anchor_norm(hit, frac - half_width, 0.06, frac + half_width, 0.94)
		hit.tooltip_text = String(actions[index]["tip"])
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit.add_theme_stylebox_override("normal", _transparent_stylebox())
		hit.add_theme_stylebox_override("hover", _transparent_stylebox())
		hit.add_theme_stylebox_override("pressed", _transparent_stylebox())
		hit.add_theme_stylebox_override("focus", _transparent_stylebox())
		hit.pressed.connect(actions[index]["cb"] as Callable)
		hit.mouse_entered.connect(_on_control_hover.bind(hit, true))
		hit.mouse_exited.connect(_on_control_hover.bind(hit, false))
		dock.add_child(hit)
		_dock_buttons.append(hit)


func _transparent_stylebox() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


## Shared hover feedback: a subtle lift + brighten, driven from the control's own
## centre so nothing drifts.
func _on_control_hover(control: Control, hovering: bool) -> void:
	if not is_instance_valid(control) or control.get("disabled"):
		return
	control.pivot_offset = control.size * 0.5
	var scale_target := Vector2(1.06, 1.06) if hovering else Vector2.ONE
	var modulate_target := Color(1.16, 1.16, 1.16, 1.0) if hovering else Color.WHITE
	var tween := create_tween().set_parallel(true)
	tween.tween_property(control, "scale", scale_target, 0.12).set_trans(Tween.TRANS_SINE)
	# The primary bar owns its own looping glow; don't fight it over `modulate`.
	if control != _play_button:
		tween.tween_property(control, "modulate", modulate_target, 0.12).set_trans(Tween.TRANS_SINE)


func _anchor_norm(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


func _build_modals() -> void:
	_modal_shade = ColorRect.new()
	_anchor_norm(_modal_shade, 0.0, 0.0, 1.0, 1.0)
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

	_settings_panel = SettingsPanel.new()
	_settings_panel.closed.connect(_on_settings_closed)
	add_child(_settings_panel)

	_clan_panel = MenuPlaceholderPanel.new()
	_clan_panel.configure("Klan")
	_clan_panel.closed.connect(_on_modal_closed)
	add_child(_clan_panel)

	_ranking_panel = MenuPlaceholderPanel.new()
	_ranking_panel.configure("Sıralama & İstatistik")
	_ranking_panel.closed.connect(_on_modal_closed)
	add_child(_ranking_panel)


func _connect_services() -> void:
	OnlineServices.regions_changed.connect(_refresh_status)
	OnlineServices.matchmaking_status_changed.connect(_on_matchmaking_status)
	OnlineServices.auth.session_changed.connect(_on_session_changed)
	NetworkSession.region_changed.connect(_refresh_status.unbind(2))
	NetworkSession.metrics_changed.connect(_refresh_status.unbind(3))
	NetworkSession.connection_state_changed.connect(_on_connection_state_changed)


func _request_online_play() -> void:
	if _starting:
		return
	if _matchmaking:
		_cancel_matchmaking()
		return
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


func _request_exit() -> void:
	if _matchmaking:
		_cancel_matchmaking()
	get_tree().quit()


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
	GameSession.prepare_online_match(assignment_variant as Dictionary)
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
	_set_matchmaking_visuals(true)
	var result: Dictionary = await OnlineServices.begin_matchmaking(GameSession.player_name)
	if generation != _matchmaking_generation:
		return
	_matchmaking = false
	_set_matchmaking_visuals(false)
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
	_set_matchmaking_visuals(false)
	_set_buttons_enabled(true)
	OnlineServices.cancel_matchmaking()
	_show_status("Eşleştirme iptal edildi", false)


## While queuing, the play bar keeps a steady amber tint (instead of a text
## change) so the player can see it is "searching — tap again to cancel".
func _set_matchmaking_visuals(active: bool) -> void:
	if not is_instance_valid(_play_button):
		return
	if active:
		if _pulse_tween != null and _pulse_tween.is_valid():
			_pulse_tween.kill()
		_play_button.modulate = Color(1.35, 1.12, 0.55, 1.0)
	else:
		_play_button.modulate = Color.WHITE
		_pulse_primary()


func _change_to_online_game() -> void:
	if not ResourceLoader.exists(ONLINE_SCENE_PATH, "PackedScene"):
		_start_error("Çevrim içi oyun sahnesi bulunamadı")
		return
	_starting = true
	_set_buttons_enabled(false)
	var error: Error = get_tree().change_scene_to_file(ONLINE_SCENE_PATH)
	if error != OK:
		_start_error("Çevrim içi sahne geçişi başarısız: %s" % error_string(error))


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


func _open_settings() -> void:
	_set_modal_visible(true)
	_settings_panel.open_panel()


func _open_clan_panel() -> void:
	_set_modal_visible(true)
	_clan_panel.open_panel()


func _open_ranking_panel() -> void:
	_set_modal_visible(true)
	_ranking_panel.open_panel()


func _on_settings_closed() -> void:
	_set_modal_visible(false)
	_refresh_status()


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
		var humans := maxi(int(status.get("human_players_waiting", 1)), 1)
		var target := maxi(int(status.get("target_players", 10)), humans)
		var seconds := maxi(int(status.get("bot_backfill_seconds_remaining", 0)), 0)
		_show_status(
			(
				"Eşleştirme • %d/%d insan • %d sn sonra botlarla tamamlanır"
				% [humans, target, seconds]
			),
			false
		)


func _on_connection_state_changed(_state: int, message: String) -> void:
	if not message.is_empty() and _matchmaking:
		_show_status(message, false)


func _refresh_status() -> void:
	if not is_instance_valid(_status_label):
		return
	if _starting or _matchmaking:
		return
	var ping_text: String = (
		"-- ms" if NetworkSession.ping_ms < 0 else "%d ms" % NetworkSession.ping_ms
	)
	var account_text: String = (
		"Hesap bağlı" if OnlineServices.auth.has_session() else "Hesap bağlı değil"
	)
	var missing: PackedStringArray = OnlineServices.get_missing_client_settings()
	if missing.is_empty():
		_show_status(
			"%s • %s • %s" % [NetworkSession.selected_region_name, ping_text, account_text], false
		)
	else:
		_show_status("Online için gerekli: %s" % ", ".join(missing), false)


func _set_modal_visible(value: bool) -> void:
	_modal_shade.visible = value
	_set_buttons_enabled(not value and not _starting and not _matchmaking)


func _set_buttons_enabled(enabled: bool) -> void:
	for button in _center_buttons:
		if is_instance_valid(button):
			# Keep the play bar tappable while queuing so it can cancel.
			button.disabled = not enabled and not (button == _play_button and _matchmaking)
	for dock_button in _dock_buttons:
		if is_instance_valid(dock_button):
			dock_button.disabled = not enabled


func _show_status(message: String, is_error: bool) -> void:
	if not is_instance_valid(_status_label):
		return
	_status_label.text = message
	_status_label.add_theme_color_override(
		"font_color", Color(1.0, 0.46, 0.36, 1.0) if is_error else Color(0.90, 0.86, 0.70, 1.0)
	)


func _start_error(message: String) -> void:
	_starting = false
	_set_buttons_enabled(true)
	_show_status(message, true)
	push_error(message)
