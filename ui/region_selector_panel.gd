class_name RegionSelectorPanel
extends PanelContainer

## Server-region picker. Every real Edgegap edge city is listed, ordered by the
## ping this device has actually measured there, with the automatically chosen
## city marked. There is no "Otomatik" entry to select: automatic is not a place
## a server can run, and offering it as a row meant a player could sit in a
## worldwide pool instead of the city nearest them.
##
## Pings are real or absent. Edgegap publishes no per-city latency endpoint, so
## a region that has never hosted one of this player's matches simply has no
## number yet and says so, rather than showing an invented one.

signal region_selected(region_id: String)
signal closed

var _list: VBoxContainer
var _buttons: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(680.0, 620.0)
	_build()
	OnlineServices.regions_changed.connect(refresh)
	# A match just played updates one region's number; redraw so the list reorders
	# without the player having to reopen it.
	NetworkSession.region_pings_changed.connect(refresh)


func open_panel() -> void:
	visible = true
	refresh()


func close_panel() -> void:
	visible = false
	closed.emit()


func refresh() -> void:
	if not is_instance_valid(_list):
		return
	for child in _list.get_children():
		child.queue_free()
	_buttons.clear()

	var regions: Array[Dictionary] = OnlineServices.get_regions()
	# Measured regions first, fastest at the top; everything unmeasured keeps the
	# catalogue order underneath so the list does not reshuffle unpredictably.
	regions.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var ping_a: int = NetworkSession.get_measured_region_ping(String(a.get("id", "")))
			var ping_b: int = NetworkSession.get_measured_region_ping(String(b.get("id", "")))
			if ping_a < 0 and ping_b < 0:
				return false
			if ping_a < 0:
				return false
			if ping_b < 0:
				return true
			return ping_a < ping_b
	)
	for region in regions:
		_add_region_card(
			String(region.get("id", "")),
			String(region.get("display_name", "")),
			String(region.get("short_name", "")),
			bool(region.get("enabled", true))
		)


func _build() -> void:
	add_theme_stylebox_override("panel", ColonyUiKit.panel_style())

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 10)
	add_child(root_box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root_box.add_child(header)
	var mark := ColonyUiKit.accent_bar(6.0, 34.0)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(mark)
	var title := Label.new()
	title.text = "SUNUCU BÖLGESİ"
	ColonyUiKit.apply_label(title, 26, 800, ColonyUiKit.ACCENT)
	header.add_child(title)

	var hint := Label.new()
	hint.text = (
		"Otomatik, IP'ne en yakın Edgegap noktasını seçer (önerilen). "
		+ "İstersen bir kıta sabitleyebilirsin — gerçek ping maçta ölçülür."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ColonyUiKit.apply_label(hint, 14, 400, ColonyUiKit.TEXT_SECONDARY)
	root_box.add_child(hint)

	root_box.add_child(ColonyUiKit.accent_bar(120.0, 2.0, Color(ColonyUiKit.ACCENT, 0.7)))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 7)
	scroll.add_child(_list)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root_box.add_child(footer)
	var close_button := Button.new()
	close_button.text = "KAPAT"
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ColonyUiKit.apply_button(close_button, &"ghost", 50.0)
	close_button.pressed.connect(close_panel)
	footer.add_child(close_button)


func _add_region_card(
	region_id: String, display_name: String, short_name: String, enabled: bool
) -> void:
	var is_active: bool = region_id == NetworkSession.selected_region_id
	var is_automatic: bool = is_active and NetworkSession.region_is_automatic
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = not enabled
	var marker: String = ""
	if is_automatic:
		marker = "★  "
	elif is_active:
		marker = "✓  "
	button.text = (
		"%s%s   ·   %s   —   %s" % [marker, display_name, short_name, _ping_label(region_id)]
	)
	ColonyUiKit.apply_button(button, &"primary" if is_active else &"ghost", 58.0)
	button.pressed.connect(_select.bind(region_id))
	_list.add_child(button)
	_buttons[region_id] = button


func _ping_label(region_id: String) -> String:
	var measured: int = NetworkSession.get_measured_region_ping(region_id)
	if measured < 0:
		return "ping ölçülmedi"
	return "%d ms" % measured


func _select(region_id: String) -> void:
	OnlineServices.select_region(region_id)
	region_selected.emit(region_id)
	close_panel()
