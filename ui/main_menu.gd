class_name ColonyMainMenu
extends Control

## Front-end built to match the supplied reference art: a full-bleed ant-colony
## background, a crowned title banner up top, four ornate stone/gold action bars
## down the centre (OYNA → solo, ÇOK OYUNCULU → online, BÖLGE → region + live
## ping, ÇIKIŞ) and a four-icon plate dock in the bottom-right corner. Labels and
## the wordmark are pre-rendered gold-textured art (Cinzel caps filled with the
## supplied gold texture) laid over the plates.

const ONLINE_SCENE_PATH: String = "res://scenes/online_game.tscn"
const MAIN_SCENE_PATH: String = "res://scenes/main_game.tscn"
const BUILD_ID: String = "PHASE-05.5-GOOGLE-BOT-BACKFILL"

const BG_PATH := "res://assets/ui/menu/frames/bg_colony.png"
const TITLE_PATH := "res://assets/ui/menu/frames/title_banner_titled.png"
const BTN_PLAY_PATH := "res://assets/ui/menu/frames/btn_play.png"
const BTN_WORLD_PATH := "res://assets/ui/menu/frames/btn_world.png"
const BTN_REGION_PATH := "res://assets/ui/menu/frames/btn_settings.png"
const BTN_EXIT_PATH := "res://assets/ui/menu/frames/btn_exit.png"
const DOCK_STRIP_PATH := "res://assets/ui/menu/frames/dock_iconed.png"
# Aspect ratio of the dock strip art; the dock box is sized to this so the baked
# icons and the invisible hit-areas over them line up on any screen shape.
const DOCK_ASPECT := 3.0
const TXT_PLAY_PATH := "res://assets/ui/menu/text/txt_play.png"
const TXT_MULTIPLAYER_PATH := "res://assets/ui/menu/text/txt_multiplayer.png"
const TXT_REGION_PATH := "res://assets/ui/menu/text/txt_region.png"
const TXT_EXIT_PATH := "res://assets/ui/menu/text/txt_exit.png"
const TXT_CANCEL_PATH := "res://assets/ui/menu/text/txt_cancel.png"
const SPINNER_PATH := "res://assets/ui/menu/frames/spinner.png"

# Normalised x-centres of the four plates baked into the dock strip art.
const DOCK_ICON_FRACTIONS: Array[float] = [0.19, 0.40, 0.60, 0.81]

var _play_button: TextureButton
var _world_button: TextureButton
var _exit_button: TextureButton
var _center_buttons: Array[TextureButton] = []
var _world_label: TextureRect
var _world_spinner: TextureRect
var _spinner_tween: Tween
var _region_button: TextureButton
var _region_ping: Label
var _dock: Control
var _dock_buttons: Array[BaseButton] = []
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
	# The global top-centre connection badge is redundant on the menu (the status
	# line already shows region/ping/account) and it overlaps the title banner, so
	# hide it here and restore it when leaving for a match.
	_set_network_overlay_visible(false)
	_build_menu()
	_connect_services()
	_refresh_status()
	OnlineServices.probe_regions()
	_play_entrance()
	_pulse_primary()
	call_deferred("_try_resume_previous_match")


func _exit_tree() -> void:
	_set_network_overlay_visible(true)


func _set_network_overlay_visible(value: bool) -> void:
	var overlay := get_node_or_null("/root/NetworkStatusOverlay")
	if overlay is CanvasLayer:
		(overlay as CanvasLayer).visible = value


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

	# Crowned title banner — the COLONY.io wordmark is baked onto the plate so it
	# can never drift off the banner on unusual screen shapes.
	var title := TextureRect.new()
	_anchor_norm(title, 0.30, -0.03, 0.70, 0.33)
	title.texture = load(TITLE_PATH)
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# Central stack of four action bars (settings lives in the dock, not here).
	var column := VBoxContainer.new()
	_anchor_norm(column, 0.34, 0.40, 0.66, 0.95)
	column.add_theme_constant_override("separation", 12)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)

	_center_buttons.clear()
	_play_button = _bar_button(BTN_PLAY_PATH, TXT_PLAY_PATH, "Oyna", _start_offline_play)
	_world_button = _bar_button(
		BTN_WORLD_PATH, TXT_MULTIPLAYER_PATH, "Çok Oyunculu", _request_online_play
	)
	_region_button = _bar_button(
		BTN_REGION_PATH, TXT_REGION_PATH, "Bölge Seç", _open_region_selector
	)
	_exit_button = _bar_button(BTN_EXIT_PATH, TXT_EXIT_PATH, "Çıkış", _request_exit)
	for button in _center_buttons:
		column.add_child(button)

	# Keep the BÖLGE wordmark on the left so the live ping has room on the right.
	var region_label := _region_button.get_node("Label") as TextureRect
	_anchor_norm(region_label, 0.24, 0.30, 0.56, 0.70)

	# Live ping / region indicator on the right of the BÖLGE bar.
	_region_ping = Label.new()
	_anchor_norm(_region_ping, 0.58, 0.30, 0.90, 0.70)
	_region_ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_region_ping.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_region_ping.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ColonyUiKit.apply_label(_region_ping, 22, 700, Color(0.96, 0.86, 0.55, 1.0))
	_region_ping.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.01, 0.95))
	_region_ping.add_theme_constant_override("outline_size", 5)
	_region_button.add_child(_region_ping)

	# The ÇOK OYUNCULU bar's label is swapped to the cancel text while queuing, and
	# a spinning ring overlays its right side.
	_world_label = _world_button.get_node("Label") as TextureRect
	_world_spinner = TextureRect.new()
	_anchor_norm(_world_spinner, 0.82, 0.24, 0.93, 0.76)
	_world_spinner.texture = load(SPINNER_PATH)
	_world_spinner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_world_spinner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_world_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_spinner.visible = false
	_world_button.add_child(_world_spinner)

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


func _bar_button(
	texture_path: String, text_path: String, tooltip: String, on_pressed: Callable
) -> TextureButton:
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

	# Gold-textured label sits on the plate, right of the emblem. The wide/short
	# box makes height the binding constraint, so every label keeps the same cap
	# height regardless of word length.
	var label := TextureRect.new()
	label.name = "Label"
	_anchor_norm(label, 0.24, 0.28, 0.92, 0.72)
	label.texture = load(text_path)
	label.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	label.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)

	_center_buttons.append(button)
	return button


## Bottom-right plate dock. The strip art (with the four gold emblems already
## baked into its octagonal sockets — trophy → ranking, ant shield → clan,
## figure → profile, gear → settings) is one image, and the dock box is sized to
## the strip's aspect ratio so it never letterboxes; four invisible hit-areas sit
## exactly over the baked plates.
func _build_dock() -> void:
	_dock = Control.new()
	_dock.name = "IconDock"
	_dock.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	add_child(_dock)

	var strip := TextureRect.new()
	_anchor_norm(strip, 0.0, 0.0, 1.0, 1.0)
	strip.texture = load(DOCK_STRIP_PATH)
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.stretch_mode = TextureRect.STRETCH_SCALE
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.add_child(strip)

	_dock_buttons.clear()
	var actions: Array[Dictionary] = [
		{"tip": "Sıralama & İstatistik", "cb": _open_ranking_panel},
		{"tip": "Klan", "cb": _open_clan_panel},
		{"tip": "Profil", "cb": _open_profile_panel},
		{"tip": "Ayarlar", "cb": _open_settings},
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
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "focus"]:
			hit.add_theme_stylebox_override(state, empty)
		hit.pressed.connect(actions[index]["cb"] as Callable)
		_dock.add_child(hit)
		_dock_buttons.append(hit)

	_relayout_dock()
	get_viewport().size_changed.connect(_relayout_dock)


## Keep the dock a fixed-aspect box pinned to the bottom-right corner so the
## baked strip fills it exactly (no letterboxing) and the hit-areas stay aligned.
func _relayout_dock() -> void:
	if not is_instance_valid(_dock):
		return
	var viewport := get_viewport_rect().size
	var dock_height: float = clampf(viewport.y * 0.135, 64.0, 150.0)
	var dock_width: float = dock_height * DOCK_ASPECT
	var margin_x: float = viewport.x * 0.012
	var margin_y: float = viewport.y * 0.02
	_dock.offset_right = -margin_x
	_dock.offset_bottom = -margin_y
	_dock.offset_left = -margin_x - dock_width
	_dock.offset_top = -margin_y - dock_height


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


## "OYNA" — a solo match against the colony AI, no server round-trip.
func _start_offline_play() -> void:
	if _starting or _matchmaking:
		return
	if not ResourceLoader.exists(MAIN_SCENE_PATH, "PackedScene"):
		_show_status("Oyun sahnesi bulunamadı", true)
		return
	_starting = true
	_set_buttons_enabled(false)
	GameSession.prepare_offline_match()
	var error: Error = get_tree().change_scene_to_file(MAIN_SCENE_PATH)
	if error != OK:
		_start_error("Oyun sahnesi geçişi başarısız: %s" % error_string(error))


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
		# A previous sign-in may be stored (only the refresh token is persisted);
		# try to silently restore it before asking the player to log in again.
		_show_status("Oturum kontrol ediliyor", false)
		var refreshed: Dictionary = await OnlineServices.auth.refresh_session()
		if not bool(refreshed.get("ok", false)) or not OnlineServices.auth.has_session():
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
	var result: Dictionary = await _request_match_assignment(generation)
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
	_show_status(_friendly_matchmaking_error(String(result.get("error", ""))), true)


## Errors that are a passing condition on the matchmaking side rather than
## anything about this player, so they are worth retrying before the player is
## ever told about them.
const RETRYABLE_MATCHMAKING_ERRORS: PackedStringArray = [
	"deploy_failed",
	"deployment_failed",
	"deploy_no_request_id",
	"matchmaking_unavailable",
	"status_failed",
	"",
]
const MATCHMAKING_RETRY_DELAYS: PackedFloat32Array = [1.5, 4.0]


## Asks for a server and quietly retries a transient refusal. A player pressing
## play does not need to know that one deployment call was refused; they need a
## match. Only when every attempt fails does the caller surface anything.
func _request_match_assignment(generation: int) -> Dictionary:
	var result: Dictionary = await OnlineServices.begin_matchmaking(GameSession.player_name)
	for delay in MATCHMAKING_RETRY_DELAYS:
		if generation != _matchmaking_generation:
			return result
		if bool(result.get("ok", false)):
			return result
		if not RETRYABLE_MATCHMAKING_ERRORS.has(String(result.get("error", ""))):
			return result
		_show_status("Sunucu hazırlanıyor", false)
		await get_tree().create_timer(delay, true, false, true).timeout
		if generation != _matchmaking_generation:
			return result
		result = await OnlineServices.begin_matchmaking(GameSession.player_name)
	return result


## Turn raw server error codes into something a player can act on. Nothing here
## describes the infrastructure: a player has no way to act on which deployment
## slot was busy, and at thousands of matches an hour that description would not
## even be true.
func _friendly_matchmaking_error(raw: String) -> String:
	match raw:
		"deploy_failed", "deployment_failed", "deploy_no_request_id":
			return "Şu an maç başlatılamadı. Tekrar dene."
		"matchmaking_not_configured":
			return "Çok oyunculu sunucu yapılandırması eksik."
		"matchmaking_unavailable", "status_failed":
			return "Eşleştirme şu an kullanılamıyor, birazdan tekrar dene."
		"authentication_required":
			return "Oturum doğrulanamadı — tekrar giriş yapman gerekebilir."
		"":
			return "Eşleştirme başarısız"
		_:
			return raw


func _cancel_matchmaking() -> void:
	_matchmaking_generation += 1
	_matchmaking = false
	_set_matchmaking_visuals(false)
	_set_buttons_enabled(true)
	OnlineServices.cancel_matchmaking()
	_show_status("Eşleştirme iptal edildi", false)


## While queuing, the ÇOK OYUNCULU bar becomes "EŞLEŞTİRMEYİ İPTAL ET" with a
## spinning ring next to it, and tapping it again cancels. The play bar keeps a
## steady amber tint too.
func _set_matchmaking_visuals(active: bool) -> void:
	if is_instance_valid(_play_button):
		if active:
			if _pulse_tween != null and _pulse_tween.is_valid():
				_pulse_tween.kill()
			_play_button.modulate = Color(1.35, 1.12, 0.55, 1.0)
		else:
			_play_button.modulate = Color.WHITE
			_pulse_primary()
	if is_instance_valid(_world_label):
		_world_label.texture = load(TXT_CANCEL_PATH if active else TXT_MULTIPLAYER_PATH)
	if is_instance_valid(_world_spinner):
		_world_spinner.visible = active
		if _spinner_tween != null and _spinner_tween.is_valid():
			_spinner_tween.kill()
		if active:
			_world_spinner.pivot_offset = _world_spinner.size * 0.5
			_world_spinner.rotation = 0.0
			_spinner_tween = create_tween().set_loops()
			_spinner_tween.tween_property(_world_spinner, "rotation", TAU, 1.0).from(0.0)


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
	# Do not auto-start matchmaking after signing in; hand control back to the
	# player so they press ÇOK OYUNCULU again when they are ready.
	_pending_online_request = false
	_set_modal_visible(false)
	_refresh_status()
	_show_status("Giriş yapıldı — başlamak için ÇOK OYUNCULU'ya bas", false)


func _on_legal_accepted() -> void:
	_pending_online_request = false
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
	_show_status("Onaylandı — başlamak için ÇOK OYUNCULU'ya bas", false)


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
	var ping_text: String = (
		"-- ms" if NetworkSession.ping_ms < 0 else "%d ms" % NetworkSession.ping_ms
	)
	# The BÖLGE bar's live ping updates even while queuing.
	if is_instance_valid(_region_ping):
		_region_ping.text = ping_text
	if not is_instance_valid(_status_label):
		return
	if _starting or _matchmaking:
		return
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
