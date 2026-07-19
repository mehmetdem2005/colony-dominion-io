class_name LegalGatePanel
extends PanelContainer

signal accepted
signal closed

var _checks: Dictionary = {}
var _continue_button: Button
var _document_viewer: PanelContainer
var _document_text: TextEdit
var _document_title: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func open_panel() -> void:
	visible = true
	_document_viewer.visible = false
	_refresh_checks()
	_update_continue_state()


func close_panel() -> void:
	if _document_viewer.visible:
		_document_viewer.visible = false
		return
	visible = false
	closed.emit()


func _build() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	position = Vector2(-390.0, -316.0)
	size = Vector2(780.0, 632.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.024, 0.025, 0.021, 0.99)
	style.border_color = Color(0.92, 0.70, 0.19, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(24)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 22.0
	style.content_margin_bottom = 22.0
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title := Label.new()
	title.text = "ÇEVRİM İÇİ HİZMETLER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 29)
	title.add_theme_color_override("font_color", Color("ffd45a"))
	box.add_child(title)

	var explanation := Label.new()
	explanation.text = (
		"Zorunlu belgelerin güncel sürümleri çevrim içi hizmete geçmeden önce ayrı ayrı "
		+ "gösterilir. İsteğe bağlı analiz izni önceden işaretlenmez."
	)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.add_theme_font_size_override("font_size", 15)
	explanation.add_theme_color_override("font_color", Color(0.78, 0.81, 0.74, 1.0))
	box.add_child(explanation)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

	for document_id in OnlineServices.legal_store.manifest.keys():
		var document: Dictionary = OnlineServices.legal_store.manifest[document_id]
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		list.add_child(row)
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 8)
		row.add_child(header)
		var check := CheckBox.new()
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.text = String(document.get("acceptance_label", document_id))
		check.add_theme_font_size_override("font_size", 17)
		check.toggled.connect(_on_check_toggled)
		header.add_child(check)
		_checks[document_id] = check
		var read_button := Button.new()
		read_button.text = "METNİ AÇ"
		read_button.custom_minimum_size = Vector2(120.0, 42.0)
		read_button.pressed.connect(_open_document.bind(String(document_id)))
		header.add_child(read_button)
		var meta := Label.new()
		meta.text = (
			"Sürüm %s%s"
			% [
				String(document.get("version", "")),
				" • Zorunlu" if bool(document.get("required", false)) else " • İsteğe bağlı",
			]
		)
		meta.add_theme_font_size_override("font_size", 13)
		meta.add_theme_color_override("font_color", Color(0.68, 0.72, 0.64, 1.0))
		row.add_child(meta)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	box.add_child(footer)
	_continue_button = Button.new()
	_continue_button.text = "KAYDET VE DEVAM ET"
	_continue_button.custom_minimum_size = Vector2(260.0, 56.0)
	_continue_button.pressed.connect(_save)
	footer.add_child(_continue_button)
	var close_button := Button.new()
	close_button.text = "KAPAT"
	close_button.custom_minimum_size = Vector2(160.0, 56.0)
	close_button.pressed.connect(close_panel)
	footer.add_child(close_button)

	_build_document_viewer()


func _build_document_viewer() -> void:
	_document_viewer = PanelContainer.new()
	_document_viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_document_viewer.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.019, 0.016, 1.0)
	style.set_corner_radius_all(20)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	_document_viewer.add_theme_stylebox_override("panel", style)
	add_child(_document_viewer)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_document_viewer.add_child(box)
	_document_title = Label.new()
	_document_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_document_title.add_theme_font_size_override("font_size", 23)
	_document_title.add_theme_color_override("font_color", Color("ffd45a"))
	box.add_child(_document_title)
	_document_text = TextEdit.new()
	_document_text.editable = false
	_document_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_document_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_document_text.add_theme_font_size_override("font_size", 16)
	box.add_child(_document_text)
	var close_document := Button.new()
	close_document.text = "METNİ KAPAT"
	close_document.custom_minimum_size = Vector2(200.0, 50.0)
	close_document.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_document.pressed.connect(func() -> void: _document_viewer.visible = false)
	box.add_child(close_document)


func _refresh_checks() -> void:
	for document_id in _checks.keys():
		var check: CheckBox = _checks[document_id]
		check.button_pressed = OnlineServices.legal_store.is_currently_accepted(String(document_id))


func _on_check_toggled(_pressed: bool) -> void:
	_update_continue_state()


func _update_continue_state() -> void:
	var all_required: bool = true
	for document_id in OnlineServices.legal_store.manifest.keys():
		var document: Dictionary = OnlineServices.legal_store.manifest[document_id]
		if not bool(document.get("required", false)):
			continue
		var check: CheckBox = _checks.get(document_id)
		if not is_instance_valid(check) or not check.button_pressed:
			all_required = false
			break
	_continue_button.disabled = not all_required


func _open_document(document_id: String) -> void:
	var document: Dictionary = OnlineServices.legal_store.manifest.get(document_id, {})
	_document_title.text = String(document.get("acceptance_label", document_id))
	_document_text.text = OnlineServices.legal_store.get_document_text(document_id)
	_document_text.scroll_vertical = 0
	_document_viewer.visible = true


func _save() -> void:
	var values: Dictionary = {}
	for document_id in _checks.keys():
		var check: CheckBox = _checks[document_id]
		values[document_id] = check.button_pressed
	var error: Error = OnlineServices.legal_store.record_acceptances(values)
	if error != OK:
		push_error("Legal acceptances could not be saved: %s" % error_string(error))
		return
	visible = false
	accepted.emit()
