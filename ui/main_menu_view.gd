class_name ColonyMainMenuView
extends Control

signal offline_requested
signal online_requested
signal resume_requested
signal settings_requested
signal quit_requested
signal region_requested
signal account_requested
signal legal_requested
signal profile_requested
signal ranking_requested
signal clan_requested

const REFERENCE_SIZE := Vector2(1280.0, 720.0)
const TEXT_PRIMARY := Color(0.97, 0.91, 0.76, 1.0)
const TEXT_SECONDARY := Color(0.78, 0.72, 0.60, 1.0)
const GOLD := Color(0.92, 0.69, 0.29, 1.0)
const PANEL_BG := Color(0.035, 0.024, 0.016, 0.90)

var player_name_input: LineEdit
var offline_button: BaseButton
var online_button: BaseButton
var resume_button: BaseButton
var region_button: BaseButton
var account_button: Button
var legal_button: BaseButton
var profile_button: BaseButton
var ranking_button: BaseButton
var clan_button: BaseButton
var settings_button: BaseButton
var dock_settings_button: BaseButton
var quit_button: BaseButton
var status_label: Label
var region_status_label: Label
var account_status_label: Label

var _stage: Control
var _online_label: Label
var _resume_label: Label
var _built: bool = false


func _ready() -> void:
	build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(_stage):
		_layout_stage()


func build() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.018, 0.012, 0.008, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_stage = Control.new()
	_stage.name = "ReferenceStage"
	_stage.size = REFERENCE_SIZE
	_stage.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_stage)

	var skin := TextureRect.new()
	skin.name = "GeneratedMainMenuSkin"
	skin.position = Vector2.ZERO
	skin.size = REFERENCE_SIZE
	skin.texture = MainMenuArtLibrary.skin_texture()
	skin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	skin.stretch_mode = TextureRect.STRETCH_SCALE
	skin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(skin)

	_build_title_controls()
	_build_primary_navigation()
	_build_bottom_dock_hits()
	_build_service_strip()
	_layout_stage()


func set_online_button_text(value: String) -> void:
	if is_instance_valid(_online_label):
		_online_label.text = value


func set_resume_button_text(value: String) -> void:
	if is_instance_valid(_resume_label):
		_resume_label.text = value
	elif is_instance_valid(resume_button) and resume_button is Button:
		(resume_button as Button).text = value


func set_account_button_text(value: String) -> void:
	if is_instance_valid(account_button):
		account_button.text = value


func set_resume_visible(value: bool) -> void:
	if is_instance_valid(resume_button):
		resume_button.visible = value


func all_interactive_buttons() -> Array[BaseButton]:
	return [
		offline_button,
		online_button,
		resume_button,
		region_button,
		account_button,
		legal_button,
		profile_button,
		ranking_button,
		clan_button,
		settings_button,
		dock_settings_button,
		quit_button,
	]


func _layout_stage() -> void:
	var available := size
	if available.x <= 1.0 or available.y <= 1.0:
		available = get_viewport_rect().size
	var factor := minf(available.x / REFERENCE_SIZE.x, available.y / REFERENCE_SIZE.y)
	factor = maxf(factor, 0.01)
	_stage.scale = Vector2.ONE * factor
	_stage.position = ((available - REFERENCE_SIZE * factor) * 0.5).floor()


func _build_title_controls() -> void:
	var title := Label.new()
	title.text = "COLONY DOMINION.IO"
	title.position = Vector2(408.0, 53.0)
	title.size = Vector2(464.0, 42.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", TEXT_PRIMARY)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 3)
	_stage.add_child(title)

	player_name_input = LineEdit.new()
	player_name_input.name = "CommanderName"
	player_name_input.placeholder_text = "Komutan adı"
	player_name_input.max_length = 16
	player_name_input.position = Vector2(510.0, 105.0)
	player_name_input.size = Vector2(260.0, 40.0)
	player_name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_name_input.add_theme_font_size_override("font_size", 17)
	player_name_input.add_theme_color_override("font_color", TEXT_PRIMARY)
	player_name_input.add_theme_color_override(
		"font_placeholder_color", Color(TEXT_SECONDARY, 0.72)
	)
	player_name_input.add_theme_stylebox_override("normal", _input_style(false))
	player_name_input.add_theme_stylebox_override("focus", _input_style(true))
	_stage.add_child(player_name_input)


func _build_primary_navigation() -> void:
	offline_button = _create_art_hit_button(Rect2(400.0, 256.0, 480.0, 78.0), "OYNA")
	offline_button.pressed.connect(func() -> void: offline_requested.emit())
	_stage.add_child(offline_button)

	online_button = _create_art_hit_button(Rect2(400.0, 339.0, 480.0, 78.0), "ÇEVRİM İÇİ")
	online_button.pressed.connect(func() -> void: online_requested.emit())
	_online_label = online_button.get_node("Text") as Label
	_stage.add_child(online_button)

	settings_button = _create_art_hit_button(Rect2(400.0, 422.0, 480.0, 78.0), "AYARLAR")
	settings_button.pressed.connect(func() -> void: settings_requested.emit())
	_stage.add_child(settings_button)

	quit_button = _create_art_hit_button(Rect2(400.0, 505.0, 480.0, 78.0), "ÇIKIŞ")
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	_stage.add_child(quit_button)


func _build_bottom_dock_hits() -> void:
	ranking_button = _create_icon_hit_button(Rect2(860.0, 615.0, 92.0, 82.0), "Sıralama")
	ranking_button.pressed.connect(func() -> void: ranking_requested.emit())
	_stage.add_child(ranking_button)

	profile_button = _create_icon_hit_button(Rect2(961.0, 615.0, 92.0, 82.0), "Profil")
	profile_button.pressed.connect(func() -> void: profile_requested.emit())
	_stage.add_child(profile_button)

	clan_button = _create_icon_hit_button(Rect2(1062.0, 615.0, 92.0, 82.0), "Klan")
	clan_button.pressed.connect(func() -> void: clan_requested.emit())
	_stage.add_child(clan_button)

	dock_settings_button = _create_icon_hit_button(Rect2(1163.0, 615.0, 92.0, 82.0), "Ayarlar")
	dock_settings_button.pressed.connect(func() -> void: settings_requested.emit())
	_stage.add_child(dock_settings_button)


func _build_service_strip() -> void:
	var panel := Panel.new()
	panel.name = "ServiceStrip"
	panel.position = Vector2(18.0, 604.0)
	panel.size = Vector2(445.0, 102.0)
	panel.add_theme_stylebox_override("panel", _service_panel_style())
	_stage.add_child(panel)

	status_label = Label.new()
	status_label.position = Vector2(16.0, 9.0)
	status_label.size = Vector2(290.0, 22.0)
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	panel.add_child(status_label)

	resume_button = _create_service_button("MAÇA DÖN")
	resume_button.position = Vector2(310.0, 6.0)
	resume_button.size = Vector2(119.0, 28.0)
	resume_button.visible = false
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	_resume_label = null
	panel.add_child(resume_button)

	region_status_label = Label.new()
	region_status_label.position = Vector2(16.0, 35.0)
	region_status_label.size = Vector2(205.0, 21.0)
	region_status_label.add_theme_font_size_override("font_size", 13)
	region_status_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	panel.add_child(region_status_label)

	account_status_label = Label.new()
	account_status_label.position = Vector2(224.0, 35.0)
	account_status_label.size = Vector2(205.0, 21.0)
	account_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	account_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	account_status_label.add_theme_font_size_override("font_size", 13)
	account_status_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	panel.add_child(account_status_label)

	var action_row := HBoxContainer.new()
	action_row.position = Vector2(12.0, 61.0)
	action_row.size = Vector2(421.0, 32.0)
	action_row.add_theme_constant_override("separation", 7)
	panel.add_child(action_row)

	region_button = _create_service_button("BÖLGE")
	region_button.pressed.connect(func() -> void: region_requested.emit())
	action_row.add_child(region_button)

	account_button = _create_service_button("GİRİŞ")
	account_button.pressed.connect(func() -> void: account_requested.emit())
	action_row.add_child(account_button)

	legal_button = _create_service_button("YASAL")
	legal_button.pressed.connect(func() -> void: legal_requested.emit())
	action_row.add_child(legal_button)


func _create_art_hit_button(rect: Rect2, text: String) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = ""
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", _transparent_button_style())
	button.add_theme_stylebox_override("hover", _art_button_style(false))
	button.add_theme_stylebox_override("pressed", _art_button_style(true))
	button.add_theme_stylebox_override("focus", _art_button_style(false))
	button.add_theme_stylebox_override("disabled", _transparent_button_style())

	var label := Label.new()
	label.name = "Text"
	label.text = text
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 94.0
	label.offset_right = -25.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_color_override("font_color", TEXT_PRIMARY)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	button.add_child(label)
	return button


func _create_icon_hit_button(rect: Rect2, tooltip: String) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = ""
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", _transparent_button_style())
	button.add_theme_stylebox_override("hover", _icon_button_style(false))
	button.add_theme_stylebox_override("pressed", _icon_button_style(true))
	button.add_theme_stylebox_override("focus", _icon_button_style(false))
	button.add_theme_stylebox_override("disabled", _transparent_button_style())
	return button


func _create_service_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(132.0, 30.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", TEXT_SECONDARY)
	button.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	button.add_theme_stylebox_override("normal", _service_button_style(false))
	button.add_theme_stylebox_override("hover", _service_button_style(true))
	button.add_theme_stylebox_override("pressed", _service_button_style(true))
	return button


func _transparent_button_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = Color(0.0, 0.0, 0.0, 0.0)
	return style


func _art_button_style(pressed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.28 if pressed else 0.06)
	style.border_color = Color(GOLD, 0.82 if pressed else 0.36)
	style.set_border_width_all(2 if pressed else 1)
	style.set_corner_radius_all(9)
	return style


func _icon_button_style(pressed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.30 if pressed else 0.08)
	style.border_color = Color(GOLD, 0.86 if pressed else 0.42)
	style.set_border_width_all(2 if pressed else 1)
	style.set_corner_radius_all(15)
	return style


func _input_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.025, 0.018, 0.92)
	style.border_color = Color(GOLD, 0.85 if focused else 0.55)
	style.set_border_width_all(2 if focused else 1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(7.0)
	return style


func _service_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = Color(GOLD, 0.48)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 10
	return style


func _service_button_style(highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.10, 0.055, 0.88 if highlighted else 0.58)
	style.border_color = Color(GOLD, 0.75 if highlighted else 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style
