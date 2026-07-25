class_name MenuPlaceholderPanel
extends PanelContainer

## A minimal, framed modal used by the main-menu icon dock for sections whose
## content is not built yet (Clan, Ranking & Statistics). The user asked to keep
## these boxes empty for now — text will be added later once the text texture and
## font are provided — so this panel deliberately shows only a titled, empty frame
## with a close button. MainMenuLayoutGuard centres every PanelContainer each
## layout pass, so no manual positioning is needed here.

signal closed

var _title_label: Label


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(640.0, 460.0)
	add_theme_stylebox_override("panel", ColonyUiKit.panel_style())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	box.add_child(header)
	var mark := ColonyUiKit.accent_bar(6.0, 34.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(mark)
	_title_label = Label.new()
	ColonyUiKit.apply_label(_title_label, 26, 800, ColonyUiKit.ACCENT)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	box.add_child(ColonyUiKit.accent_bar(140.0, 3.0, Color(ColonyUiKit.ACCENT, 0.85)))

	# Empty content region — intentionally left blank for now.
	var content := Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(content)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(footer)
	var close_button := Button.new()
	close_button.text = "KAPAT"
	ColonyUiKit.apply_button(close_button, &"ghost", 46.0)
	close_button.custom_minimum_size.x = 160.0
	close_button.pressed.connect(_close)
	footer.add_child(close_button)


func configure(title: String) -> void:
	if _title_label != null:
		_title_label.text = title.to_upper()


func open_panel() -> void:
	visible = true


func _close() -> void:
	visible = false
	closed.emit()
