class_name SettingsPanel
extends PanelContainer
## Reusable modal settings panel with audio, display and controls tabs.
##
## Audio settings delegate to the AudioSystem autoload, display settings to
## DisplaySettings and key rebinding to InputSettings. The same instance is used
## from the main menu and from the in-game HUD.

signal closed

const _ACCENT: Color = Color("ffd45a")

var _tabs: TabContainer
var _control_rows: Dictionary = {}
var _listening_action: StringName = &""
var _listening_button: Button
var _rebind_status: Label


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func open_panel() -> void:
	visible = true
	_refresh_all()


func close_panel() -> void:
	_cancel_listening()
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if _listening_action == &"" or not visible:
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	get_viewport().set_input_as_handled()
	if key_event.keycode == KEY_ESCAPE:
		_cancel_listening()
		return
	if key_event.physical_keycode <= 0:
		return
	var action: StringName = _listening_action
	InputSettings.rebind(action, key_event.physical_keycode)
	_cancel_listening()
	_refresh_controls()
	AudioSystem.play_ui(&"ui_select")


func _build() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	position = Vector2(-390.0, -312.0)
	size = Vector2(780.0, 624.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.026, 0.022, 0.98)
	style.border_color = Color(0.92, 0.70, 0.19, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(24)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	add_theme_stylebox_override("panel", style)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 12)
	add_child(root_box)

	var title := Label.new()
	title.text = "AYARLAR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", _ACCENT)
	root_box.add_child(title)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 18)
	root_box.add_child(_tabs)
	_tabs.add_child(_build_audio_tab())
	_tabs.add_child(_build_display_tab())
	_tabs.add_child(_build_controls_tab())

	var close_button := Button.new()
	close_button.text = "KAPAT"
	close_button.custom_minimum_size = Vector2(0.0, 50.0)
	close_button.add_theme_font_size_override("font_size", 18)
	close_button.pressed.connect(close_panel)
	root_box.add_child(close_button)


func _build_audio_tab() -> Control:
	var scroll := _make_tab_scroll("Ses")
	var box: VBoxContainer = scroll.get_child(0)
	_add_slider_row(box, "Ana ses", &"master")
	_add_slider_row(box, "Müzik", &"music")
	_add_slider_row(box, "Efektler", &"sfx")
	_add_slider_row(box, "Çevre sesi", &"ambient")
	_add_slider_row(box, "Arayüz sesi", &"ui")
	_add_audio_toggle(box, "Titreşim (dokunmatik)", &"vibration")
	_add_audio_toggle(box, "Arka planda sesi kapat", &"mute_background")
	return scroll


func _build_display_tab() -> Control:
	var scroll := _make_tab_scroll("Görüntü")
	var box: VBoxContainer = scroll.get_child(0)
	var window_option := _add_option_row(box, "Pencere modu", ["Pencere", "Tam ekran"])
	window_option.item_selected.connect(_on_window_mode_selected)
	window_option.select(int(DisplaySettings.get_value("window_mode")))

	var vsync_toggle := _add_display_toggle(box, "Dikey senkron (V-Sync)")
	vsync_toggle.button_pressed = bool(DisplaySettings.get_value("vsync"))
	vsync_toggle.toggled.connect(_on_vsync_toggled)

	var fps_option := _add_option_row(box, "FPS sınırı", ["30", "60", "120", "Sınırsız"])
	fps_option.item_selected.connect(_on_fps_selected)
	fps_option.select(_fps_index(int(DisplaySettings.get_value("max_fps"))))

	var quality_option := _add_option_row(box, "Grafik kalitesi", ["Düşük", "Orta", "Yüksek"])
	quality_option.item_selected.connect(_on_quality_selected)
	quality_option.select(int(DisplaySettings.get_value("quality")))

	var show_fps_toggle := _add_display_toggle(box, "FPS sayacını göster")
	show_fps_toggle.button_pressed = bool(DisplaySettings.get_value("show_fps"))
	show_fps_toggle.toggled.connect(_on_show_fps_toggled)
	return scroll


func _build_controls_tab() -> Control:
	var scroll := _make_tab_scroll("Kontroller")
	var box: VBoxContainer = scroll.get_child(0)

	_rebind_status = Label.new()
	_rebind_status.text = "Değiştirmek için tuşa dokun, sonra yeni tuşa bas. (İptal: Esc)"
	_rebind_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rebind_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rebind_status.add_theme_font_size_override("font_size", 14)
	_rebind_status.add_theme_color_override("font_color", Color(0.77, 0.80, 0.73, 1.0))
	box.add_child(_rebind_status)

	var labels: Dictionary = InputSettings.get_action_labels()
	for action in InputSettings.MANAGED_ACTIONS:
		_add_control_row(box, action, String(labels.get(action, String(action))))

	var reset_button := Button.new()
	reset_button.text = "TÜM TUŞLARI VARSAYILANA DÖNDÜR"
	reset_button.custom_minimum_size = Vector2(0.0, 46.0)
	reset_button.add_theme_font_size_override("font_size", 15)
	reset_button.pressed.connect(_on_reset_controls)
	box.add_child(reset_button)
	return scroll


func _make_tab_scroll(tab_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	return scroll


func _add_slider_row(parent: VBoxContainer, label_text: String, setting_id: StringName) -> void:
	var row := _make_row(parent, label_text)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(360.0, 36.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(AudioSystem.get_setting(setting_id))
	slider.value_changed.connect(_on_volume_changed.bind(setting_id))
	row.add_child(slider)


func _add_audio_toggle(parent: VBoxContainer, label_text: String, setting_id: StringName) -> void:
	var toggle := CheckButton.new()
	toggle.text = label_text
	toggle.custom_minimum_size = Vector2(0.0, 40.0)
	toggle.button_pressed = bool(AudioSystem.get_setting(setting_id))
	toggle.add_theme_font_size_override("font_size", 16)
	toggle.toggled.connect(_on_audio_toggle_changed.bind(setting_id))
	parent.add_child(toggle)


func _add_option_row(parent: VBoxContainer, label_text: String, items: Array) -> OptionButton:
	var row := _make_row(parent, label_text)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(360.0, 40.0)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_theme_font_size_override("font_size", 16)
	for item in items:
		option.add_item(String(item))
	row.add_child(option)
	return option


func _add_display_toggle(parent: VBoxContainer, label_text: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = label_text
	toggle.custom_minimum_size = Vector2(0.0, 40.0)
	toggle.add_theme_font_size_override("font_size", 16)
	parent.add_child(toggle)
	return toggle


func _add_control_row(parent: VBoxContainer, action: StringName, label_text: String) -> void:
	var row := _make_row(parent, label_text)
	var button := Button.new()
	button.custom_minimum_size = Vector2(240.0, 42.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 17)
	button.text = InputSettings.get_key_label(action)
	button.pressed.connect(_on_rebind_pressed.bind(action, button))
	row.add_child(button)
	_control_rows[action] = button


func _make_row(parent: VBoxContainer, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 44.0)
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(220.0, 40.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.94, 0.91, 0.78, 1.0))
	row.add_child(label)
	return row


func _fps_index(max_fps: int) -> int:
	var index: int = DisplaySettings.FPS_OPTIONS.find(max_fps)
	return index if index >= 0 else 1


func _on_volume_changed(value: float, setting_id: StringName) -> void:
	AudioSystem.set_volume(setting_id, value)


func _on_audio_toggle_changed(enabled: bool, setting_id: StringName) -> void:
	AudioSystem.set_toggle(setting_id, enabled)


func _on_window_mode_selected(index: int) -> void:
	DisplaySettings.set_value("window_mode", index)


func _on_vsync_toggled(enabled: bool) -> void:
	DisplaySettings.set_value("vsync", enabled)


func _on_fps_selected(index: int) -> void:
	var options: Array[int] = DisplaySettings.FPS_OPTIONS
	if index >= 0 and index < options.size():
		DisplaySettings.set_value("max_fps", options[index])


func _on_quality_selected(index: int) -> void:
	DisplaySettings.set_value("quality", index)


func _on_show_fps_toggled(enabled: bool) -> void:
	DisplaySettings.set_value("show_fps", enabled)


func _on_rebind_pressed(action: StringName, button: Button) -> void:
	_cancel_listening()
	_listening_action = action
	_listening_button = button
	button.text = "… tuşa bas"
	button.add_theme_color_override("font_color", _ACCENT)
	if is_instance_valid(_rebind_status):
		_rebind_status.text = "Yeni tuşa bas… (İptal için Esc)"


func _on_reset_controls() -> void:
	_cancel_listening()
	InputSettings.reset_all()
	_refresh_controls()
	AudioSystem.play_ui(&"ui_select")


func _cancel_listening() -> void:
	if _listening_action == &"":
		return
	if is_instance_valid(_listening_button):
		_listening_button.remove_theme_color_override("font_color")
		_listening_button.text = InputSettings.get_key_label(_listening_action)
	_listening_action = &""
	_listening_button = null
	if is_instance_valid(_rebind_status):
		_rebind_status.text = "Değiştirmek için tuşa dokun, sonra yeni tuşa bas. (İptal: Esc)"


func _refresh_all() -> void:
	_refresh_controls()


func _refresh_controls() -> void:
	for action in _control_rows:
		var button: Button = _control_rows[action]
		if is_instance_valid(button):
			button.text = InputSettings.get_key_label(action)
