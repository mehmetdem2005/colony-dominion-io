class_name LegalConsentCard
extends PanelContainer

signal selection_changed(document_id: String, selected: bool)
signal document_requested(document_id: String)

var _document_id: String = ""
var _title_text: String = ""
var _version_text: String = ""
var _required: bool = false
var _toggle_button: Button
var _indicator: PanelContainer
var _indicator_label: Label
var _title_label: Label
var _meta_label: Label
var _read_button: Button


func configure(document_id: String, title: String, version: String, required: bool) -> void:
	_document_id = document_id
	_title_text = title
	_version_text = version
	_required = required
	if is_inside_tree():
		_apply_content()


func _ready() -> void:
	custom_minimum_size.y = 102.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_apply_content()
	_refresh_visuals()


func set_selected(value: bool, emit_change: bool = false) -> void:
	if not is_instance_valid(_toggle_button):
		return
	_toggle_button.set_pressed_no_signal(value)
	_refresh_visuals()
	if emit_change:
		selection_changed.emit(_document_id, value)


func is_selected() -> bool:
	return is_instance_valid(_toggle_button) and _toggle_button.button_pressed


func focus_selection() -> void:
	if is_instance_valid(_toggle_button):
		_toggle_button.grab_focus()


func _build() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	_toggle_button = Button.new()
	_toggle_button.toggle_mode = true
	_toggle_button.text = ""
	_toggle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toggle_button.custom_minimum_size.y = 80.0
	_toggle_button.focus_mode = Control.FOCUS_ALL
	_toggle_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_toggle_button.toggled.connect(_on_toggled)
	row.add_child(_toggle_button)
	_apply_toggle_button_styles()

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_toggle_button.add_child(margin)

	var selection_row := HBoxContainer.new()
	selection_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_row.add_theme_constant_override("separation", 14)
	margin.add_child(selection_row)

	_indicator = PanelContainer.new()
	_indicator.custom_minimum_size = Vector2(42.0, 42.0)
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_row.add_child(_indicator)
	_indicator_label = Label.new()
	_indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_indicator_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_indicator_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ColonyUiKit.apply_label(_indicator_label, 25, 800, Color("17130a"))
	_indicator.add_child(_indicator_label)

	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_theme_constant_override("separation", 5)
	selection_row.add_child(copy)
	_title_label = Label.new()
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ColonyUiKit.apply_label(_title_label, 17, 650, ColonyUiKit.TEXT_PRIMARY)
	copy.add_child(_title_label)
	_meta_label = Label.new()
	_meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ColonyUiKit.apply_label(_meta_label, 13, 500, ColonyUiKit.TEXT_MUTED)
	copy.add_child(_meta_label)

	_read_button = Button.new()
	_read_button.text = "METNİ GÖR"
	_read_button.custom_minimum_size = Vector2(124.0, 52.0)
	_read_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ColonyUiKit.apply_button(_read_button, &"ghost", 52.0)
	_read_button.pressed.connect(func() -> void: document_requested.emit(_document_id))
	row.add_child(_read_button)


func _apply_content() -> void:
	if not is_instance_valid(_title_label):
		return
	_title_label.text = _title_text.trim_suffix(".")
	var public_version: String = _version_text.get_slice("-", 0)
	_meta_label.text = (
		"Sürüm %s  •  %s" % [public_version, "ZORUNLU" if _required else "İSTEĞE BAĞLI"]
	)


func _on_toggled(selected: bool) -> void:
	_refresh_visuals()
	selection_changed.emit(_document_id, selected)


func _refresh_visuals() -> void:
	if not is_instance_valid(_toggle_button):
		return
	var selected := _toggle_button.button_pressed
	add_theme_stylebox_override("panel", ColonyUiKit.card_style(selected))
	_indicator.add_theme_stylebox_override(
		"panel",
		ColonyUiKit.rounded_style(
			ColonyUiKit.ACCENT if selected else Color("0c0f0f"),
			ColonyUiKit.ACCENT if selected else ColonyUiKit.BORDER_STRONG,
			2,
			11
		)
	)
	_indicator_label.text = "✓" if selected else ""
	_title_label.add_theme_color_override(
		"font_color", ColonyUiKit.TEXT_PRIMARY if selected else Color("e2e5df")
	)


func _apply_toggle_button_styles() -> void:
	var empty := StyleBoxEmpty.new()
	_toggle_button.add_theme_stylebox_override("normal", empty)
	_toggle_button.add_theme_stylebox_override("hover", empty)
	_toggle_button.add_theme_stylebox_override("pressed", empty)
	_toggle_button.add_theme_stylebox_override("disabled", empty)
	var focus := ColonyUiKit.rounded_style(
		Color.TRANSPARENT, Color(ColonyUiKit.ACCENT, 0.9), 2, 13
	)
	_toggle_button.add_theme_stylebox_override("focus", focus)
