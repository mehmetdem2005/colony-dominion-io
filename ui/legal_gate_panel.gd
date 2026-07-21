class_name LegalGatePanel
extends PanelContainer

signal accepted
signal closed

var _cards: Dictionary = {}
var _continue_button: Button
var _progress_label: Label
var _status_panel: PanelContainer
var _document_viewer: PanelContainer
var _document_text: RichTextLabel
var _document_title: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(720.0, 650.0)
	_build()


func open_panel() -> void:
	visible = true
	_document_viewer.visible = false
	_refresh_cards()
	_update_continue_state()
	call_deferred("_focus_first_incomplete")


func close_panel() -> void:
	if _document_viewer.visible:
		_document_viewer.visible = false
		return
	visible = false
	closed.emit()


func _build() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	position = Vector2(-390.0, -330.0)
	size = Vector2(780.0, 660.0)
	add_theme_stylebox_override("panel", ColonyUiKit.panel_style())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	var eyebrow := Label.new()
	eyebrow.text = "HESAP GÜVENLİĞİ VE YASAL ONAY"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ColonyUiKit.apply_label(eyebrow, 12, 700, ColonyUiKit.ACCENT)
	box.add_child(eyebrow)

	var title := Label.new()
	title.text = "Çevrim içi hizmetlere geç"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ColonyUiKit.apply_label(title, 30, 750, ColonyUiKit.TEXT_PRIMARY)
	box.add_child(title)

	var explanation := Label.new()
	explanation.text = (
		"Devam etmek için zorunlu belgeleri onayla. Her kartın tamamı dokunulabilir; "
		+ "analiz izni isteğe bağlıdır ve otomatik seçilmez."
	)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.custom_minimum_size.y = 46.0
	ColonyUiKit.apply_label(explanation, 15, 450, ColonyUiKit.TEXT_SECONDARY)
	box.add_child(explanation)

	_status_panel = PanelContainer.new()
	_status_panel.add_theme_stylebox_override("panel", ColonyUiKit.status_style(&"accent"))
	box.add_child(_status_panel)
	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ColonyUiKit.apply_label(_progress_label, 14, 600, ColonyUiKit.TEXT_SECONDARY)
	_status_panel.add_child(_progress_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	box.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	for document_id_variant in OnlineServices.legal_store.manifest.keys():
		var document_id := String(document_id_variant)
		var document: Dictionary = OnlineServices.legal_store.manifest[document_id]
		var card := LegalConsentCard.new()
		card.configure(
			document_id,
			String(document.get("acceptance_label", document_id)),
			String(document.get("version", "")),
			bool(document.get("required", false))
		)
		card.selection_changed.connect(_on_card_selection_changed)
		card.document_requested.connect(_open_document)
		list.add_child(card)
		_cards[document_id] = card

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	box.add_child(footer)

	_continue_button = Button.new()
	_continue_button.text = "ONAYLARI KAYDET VE DEVAM ET"
	_continue_button.custom_minimum_size = Vector2(340.0, 58.0)
	ColonyUiKit.apply_button(_continue_button, &"primary", 58.0)
	_continue_button.pressed.connect(_save)
	footer.add_child(_continue_button)

	var close_button := Button.new()
	close_button.text = "ŞİMDİ DEĞİL"
	close_button.custom_minimum_size = Vector2(180.0, 58.0)
	ColonyUiKit.apply_button(close_button, &"ghost", 58.0)
	close_button.pressed.connect(close_panel)
	footer.add_child(close_button)

	_build_document_viewer()


func _build_document_viewer() -> void:
	_document_viewer = PanelContainer.new()
	_document_viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_document_viewer.visible = false
	_document_viewer.mouse_filter = Control.MOUSE_FILTER_STOP
	_document_viewer.z_index = 50
	_document_viewer.add_theme_stylebox_override(
		"panel",
		ColonyUiKit.rounded_style(
			Color("0b0d0d"), Color(ColonyUiKit.ACCENT, 0.85), 2, 22, Vector4(24.0, 22.0, 24.0, 22.0)
		)
	)
	add_child(_document_viewer)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_document_viewer.add_child(box)

	_document_title = Label.new()
	_document_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_document_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ColonyUiKit.apply_label(_document_title, 24, 750, ColonyUiKit.TEXT_PRIMARY)
	box.add_child(_document_title)

	_document_text = RichTextLabel.new()
	_document_text.bbcode_enabled = false
	_document_text.selection_enabled = true
	_document_text.context_menu_enabled = true
	_document_text.scroll_active = true
	_document_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_document_text.add_theme_stylebox_override(
		"normal",
		ColonyUiKit.rounded_style(
			Color("111414"), ColonyUiKit.BORDER, 1, 14, Vector4(18.0, 16.0, 18.0, 16.0)
		)
	)
	ColonyUiKit.apply_rich_text(_document_text, 16, 450, Color("e4e7e1"))
	box.add_child(_document_text)

	var close_document := Button.new()
	close_document.text = "BELGEYE DÖN"
	close_document.custom_minimum_size = Vector2(220.0, 54.0)
	close_document.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ColonyUiKit.apply_button(close_document, &"secondary", 54.0)
	close_document.pressed.connect(func() -> void: _document_viewer.visible = false)
	box.add_child(close_document)


func _refresh_cards() -> void:
	for document_id_variant in _cards.keys():
		var document_id := String(document_id_variant)
		var card := _cards[document_id] as LegalConsentCard
		if is_instance_valid(card):
			card.set_selected(OnlineServices.legal_store.is_currently_accepted(document_id))


func _on_card_selection_changed(_document_id: String, _selected: bool) -> void:
	_update_continue_state()
	AudioSystem.play_ui(&"ui_select")


func _update_continue_state() -> void:
	var selected_required := 0
	var total_required := 0
	for document_id_variant in OnlineServices.legal_store.manifest.keys():
		var document_id := String(document_id_variant)
		var document: Dictionary = OnlineServices.legal_store.manifest[document_id]
		if not bool(document.get("required", false)):
			continue
		total_required += 1
		var card := _cards.get(document_id) as LegalConsentCard
		if is_instance_valid(card) and card.is_selected():
			selected_required += 1

	var complete := total_required > 0 and selected_required == total_required
	_continue_button.disabled = not complete
	_progress_label.text = (
		"Zorunlu onaylar tamamlandı — devam edebilirsin"
		if complete
		else "Zorunlu onay: %d / %d" % [selected_required, total_required]
	)
	_status_panel.add_theme_stylebox_override(
		"panel", ColonyUiKit.status_style(&"success" if complete else &"accent")
	)
	_progress_label.add_theme_color_override(
		"font_color", ColonyUiKit.SUCCESS if complete else ColonyUiKit.TEXT_SECONDARY
	)


func _open_document(document_id: String) -> void:
	var document: Dictionary = OnlineServices.legal_store.manifest.get(document_id, {})
	_document_title.text = String(document.get("acceptance_label", document_id)).trim_suffix(".")
	_document_text.text = _clean_document_text(
		OnlineServices.legal_store.get_document_text(document_id)
	)
	_document_text.scroll_to_line(0)
	_document_viewer.visible = true


func _save() -> void:
	if _continue_button.disabled:
		_update_continue_state()
		return
	var values: Dictionary = {}
	for document_id_variant in _cards.keys():
		var document_id := String(document_id_variant)
		var card := _cards[document_id] as LegalConsentCard
		values[document_id] = is_instance_valid(card) and card.is_selected()
	var error: Error = OnlineServices.legal_store.record_acceptances(values)
	if error != OK:
		_progress_label.text = "Onaylar kaydedilemedi. Tekrar dene."
		_progress_label.add_theme_color_override("font_color", ColonyUiKit.DANGER)
		_status_panel.add_theme_stylebox_override("panel", ColonyUiKit.status_style(&"danger"))
		push_error("Legal acceptances could not be saved: %s" % error_string(error))
		return
	visible = false
	accepted.emit()


func _focus_first_incomplete() -> void:
	for document_id_variant in OnlineServices.legal_store.manifest.keys():
		var document_id := String(document_id_variant)
		var document: Dictionary = OnlineServices.legal_store.manifest[document_id]
		var card := _cards.get(document_id) as LegalConsentCard
		if (
			bool(document.get("required", false))
			and is_instance_valid(card)
			and not card.is_selected()
		):
			card.focus_selection()
			return
	_continue_button.grab_focus()


func _clean_document_text(value: String) -> String:
	var lines := value.split("\n")
	var cleaned := PackedStringArray()
	for line in lines:
		var text := String(line)
		while text.begins_with("#"):
			text = text.trim_prefix("#")
		cleaned.append(text.strip_edges() if text.begins_with(" ") else text)
	return "\n".join(cleaned).strip_edges()
