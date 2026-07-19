extends CanvasLayer

var _label: Label


func _ready() -> void:
	layer = 240
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		return
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.position = Vector2(-108.0, 66.0)
	_label.size = Vector2(216.0, 34.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.93, 0.95, 0.88, 1.0))
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_label)
	NetworkSession.mode_changed.connect(_refresh.unbind(1))
	NetworkSession.region_changed.connect(_refresh.unbind(2))
	NetworkSession.metrics_changed.connect(_refresh.unbind(3))
	NetworkSession.connection_state_changed.connect(_refresh.unbind(2))
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_label):
		return
	_label.text = NetworkSession.get_status_text()
	if NetworkSession.mode == NetworkSession.SessionMode.OFFLINE:
		_label.add_theme_color_override("font_color", Color(0.80, 0.82, 0.76, 1.0))
	elif NetworkSession.ping_ms < 0:
		_label.add_theme_color_override("font_color", Color(0.90, 0.78, 0.35, 1.0))
	elif NetworkSession.ping_ms <= 70:
		_label.add_theme_color_override("font_color", Color(0.44, 1.0, 0.54, 1.0))
	elif NetworkSession.ping_ms <= 140:
		_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32, 1.0))
	else:
		_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.34, 1.0))
