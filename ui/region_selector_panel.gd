class_name RegionSelectorPanel
extends PanelContainer

signal region_selected(region_id: String)
signal closed

var _list: VBoxContainer
var _buttons: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	OnlineServices.regions_changed.connect(refresh)


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
	_add_region_row("auto", "Otomatik", "AUTO", _get_auto_metrics(), true)
	for region in OnlineServices.get_regions():
		_add_region_row(
			String(region.get("id", "")),
			String(region.get("display_name", "")),
			String(region.get("short_name", "")),
			region.get("metrics", {}) as Dictionary,
			bool(region.get("enabled", true))
		)


func _build() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	position = Vector2(-350.0, -292.0)
	size = Vector2(700.0, 584.0)
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
	title.text = "SUNUCU BÖLGESİ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("ffd45a"))
	root_box.add_child(title)

	var hint := Label.new()
	hint.text = "Otomatik seçim ping, jitter, paket kaybı ve sunucu uygunluğunu karşılaştırır."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.77, 0.80, 0.73, 1.0))
	root_box.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	root_box.add_child(footer)

	var refresh_button := Button.new()
	refresh_button.text = "PING'LERİ YENİLE"
	refresh_button.custom_minimum_size = Vector2(220.0, 50.0)
	refresh_button.pressed.connect(OnlineServices.probe_regions)
	footer.add_child(refresh_button)

	var close_button := Button.new()
	close_button.text = "KAPAT"
	close_button.custom_minimum_size = Vector2(160.0, 50.0)
	close_button.pressed.connect(close_panel)
	footer.add_child(close_button)


func _add_region_row(
	region_id: String, display_name: String, short_name: String, metrics: Dictionary, enabled: bool
) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(620.0, 58.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 18)
	var is_selected: bool = (
		region_id == NetworkSession.preferred_region_id
		or (region_id == "auto" and NetworkSession.preferred_region_id == "auto")
	)
	button.text = (
		"%s%s  •  %s  •  %s"
		% [
			"✓ " if is_selected else "",
			display_name,
			short_name,
			_format_metrics(metrics),
		]
	)
	button.disabled = not enabled
	button.tooltip_text = _metrics_tooltip(metrics)
	button.pressed.connect(_select.bind(region_id))
	_list.add_child(button)
	_buttons[region_id] = button


func _select(region_id: String) -> void:
	OnlineServices.select_region(region_id)
	region_selected.emit(region_id)
	close_panel()


func _get_auto_metrics() -> Dictionary:
	var best_id: String = OnlineServices.region_probe.get_best_region_id()
	return OnlineServices.region_probe.get_metrics(best_id) if not best_id.is_empty() else {}


func _format_metrics(metrics: Dictionary) -> String:
	if metrics.is_empty() or not bool(metrics.get("configured", false)):
		return "Yapılandırılmadı"
	if not bool(metrics.get("available", false)):
		return "Ulaşılamıyor"
	var ping: int = int(metrics.get("ping_ms", -1))
	var jitter: int = int(metrics.get("jitter_ms", -1))
	var loss: int = roundi(float(metrics.get("packet_loss", 0.0)) * 100.0)
	return "%d ms  •  jitter %d  •  kayıp %%%d" % [ping, jitter, loss]


func _metrics_tooltip(metrics: Dictionary) -> String:
	if not bool(metrics.get("configured", false)):
		return "Bu bölgenin probe_url değeri backend_config.json içinde henüz tanımlanmadı."
	return _format_metrics(metrics)
